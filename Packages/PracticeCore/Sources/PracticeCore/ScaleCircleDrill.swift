import TheoryCore

extension DrillKind {
    public static let scaleCircle = DrillKind(
        id: "scaleCircle", module: .scales, title: "Scale circle",
        instructions: "The scale up through the position, then the next key round the circle down through the nearest one, "
            + "and so on through all twelve.",
        symbol: "arrow.triangle.2.circlepath", traits: .goesRoundTheCircle, rules: ScaleCircleRules.self)
}

extension DrillSetup {
    /// Scale circle only: its twelve positions (`Fretboard.scaleCirclePositions`), from the theme's key and position,
    /// or without one the chosen scale's. Fewer when the circle can't go round; empty when the position isn't on the
    /// neck.
    public var scaleCirclePositions: [Position] {
        let start = theme.map { $0.position(on: fretboard) } ?? position
        return start.map { fretboard.scaleCirclePositions(from: $0, going: ScaleCircleRules.firstDirection) } ?? []
    }
}

/// Scale circle: twelve one-way passes round the circle of fifths, the first up through the start position and then
/// each key in turn down or up through its nearest position (TheoryCore's Scale circle positions). No clicks and no
/// timeout: the circle's time and wrong notes are set against the best, as in the Note circle. Each pass fades at its
/// scale kind and position's level from when it starts, expecting a second a note; when one ends, the next key's
/// position is shown whole at once, its first note ringed. One attempt per note, grouped by pass, all in circle 0.
public struct ScaleCircleRules: DrillRules {
    public static var kind: DrillKind { .scaleCircle }

    static let firstDirection = PassDirection.up
    /// How long a pass should take, a note at a time: what its fade time is a share of.
    static let expectedTimePerNote = Duration.seconds(1)

    public let setup: DrillSetup
    private let positions: [Position]
    /// The current pass's index in `positions`, and its notes still to prompt.
    private var pass = -1
    private var queue: [FretboardLocation] = []
    private var passAttempts: [Attempt] = []
    /// When the current pass's first note's timer started: its fade starts then.
    private var passStart: Duration = .zero
    private var level = FadeLevel.first
    private var isHinted = false
    private var isHintShown = false
    private var reached: FadeLevels

    public init(setup: DrillSetup) {
        self.setup = setup
        positions = setup.scaleCirclePositions
        reached = setup.fadeLevels
    }

    public mutating func begin() {
        pass = -1
        queue = []
    }

    public var nothingToPromptReason: String? {
        if positions.isEmpty { return DrillSetup.noPositionReason }
        return positions.count < 12 ? "The circle can’t go round from this position: choose another." : nil
    }

    public mutating func nextPrompt(after previous: NotePrompt?) -> NotePrompt? {
        if queue.isEmpty {
            guard pass + 1 < positions.count else { return nil }
            pass += 1
            queue = order(of: pass)
            passAttempts = []
            isHinted = isHintShown
            let position = positions[pass]
            level = setup.options.pass.fadeLevel ?? reached.level(of: subject(of: position))
        }
        let location = queue.removeFirst()
        return NotePrompt(name: setup.fretboard.name(at: location, in: positions[pass].scale), string: location.string,
                          target: location, sweep: pass)
    }

    private func direction(of pass: Int) -> PassDirection {
        pass.isMultiple(of: 2) ? Self.firstDirection : Self.firstDirection.reversed
    }

    private func order(of pass: Int) -> [FretboardLocation] {
        setup.fretboard.passOrder(of: positions[pass], going: direction(of: pass))
    }

    private func subject(of position: Position) -> FadeLevels.Subject {
        FadeLevels.Subject(tuning: setup.fretboard.tuning, scaleKind: position.scale.kind, position: position.id)
    }

    public func judge(_ answer: DrillAnswer, for prompt: NotePrompt) -> DrillJudgement {
        setup.judgeExactPitch(answer, for: prompt)
    }

    public func correctLocations(for prompt: NotePrompt) -> [FretboardLocation] {
        prompt.target.map { [$0] } ?? []
    }

    public func group(for prompt: NotePrompt) -> AttemptGroup? {
        guard let pass = prompt.sweep else { return nil }
        let order = order(of: pass)
        return AttemptGroup(number: pass, size: order.count, place: order.firstIndex { $0 == prompt.target }, circle: 0)
    }

    public func facts(for prompt: NotePrompt) -> AttemptFacts? {
        guard let pass = prompt.sweep else { return nil }
        let position = positions[pass], order = order(of: pass)
        let first = order.first.map { setup.fretboard.pitch(at: $0).pitchClass }
        return .pass(PassFacts(scale: position.scale, position: position.id,
                               startDegree: first.flatMap(position.scale.degree) ?? Scale.Degree(1),
                               tempo: nil, signature: nil, direction: direction(of: pass), fadeLevel: level,
                               hinted: isHinted, clickOffset: nil, inputDelay: setup.inputDelay))
    }

    public mutating func dealtWith(_ attempt: Attempt) {
        passAttempts.append(attempt)
        if queue.isEmpty { reached.add([PassResult(attempts: passAttempts)], in: setup.fretboard.tuning) }
    }

    public mutating func timerStarted(at time: Duration) {
        if passAttempts.isEmpty { passStart = time }
    }

    public var isTimed: Bool { false }

    public mutating func hint(isShown: Bool) {
        isHintShown = isShown
        if isShown { isHinted = true }
    }

    public var fadeLevels: FadeLevels? {
        get { reached }
        set { if let newValue { reached = newValue } }
    }

    /// Straight on, within a pass and into the next key, with the clock running; the circle's end is held long enough
    /// to read its time.
    public func transition(after attempt: Attempt) -> DrillTransition {
        queue.isEmpty && pass + 1 == positions.count
            ? DrillTransition(pause: DrillTiming.revealPause, timesFromLastPrompt: false) : .continuous
    }

    public var resumeRule: DrillResumeRule { .samePrompt(keepingWrongAnswers: true) }

    public func display(of moment: DrillMoment) -> DrillDisplay {
        let pass = moment.prompt.sweep ?? 0
        let position = positions[pass], scale = position.scale
        var display = DrillDisplay(standard: moment, in: setup)
        display.headline = scale.name
        display.subline = "\(scale.kind.name) · \(position.name) · \(direction(of: pass).text)"
        display.highlightedStrings = []
        if case .wrong(let played) = moment.phase { display.feedback = "You played \(scale.spell(played))" }
        let done = moment.attempts.filter { $0.prompt.sweep == pass }
        display.markers = markers(of: pass, done: done, at: moment.now)
        let order = order(of: pass)
        display.pass = PassProgress(
            notes: order.map(setup.fretboard.pitch).relativeHeights.enumerated().map { index, height in
                let state: DrillDisplay.Chip.State = if index < done.count { done[index].skipped ? .skipped : .found }
                    else { index == done.count ? .current : .waiting }
                return PassProgress.Note(height: height, state: state)
            },
            countIn: nil, evenness: nil, settings: settings, fretWindow: position.fretWindow)
        display.circle = progress(at: moment)
        return display
    }

    /// What the pass is played at: only its fade level means anything.
    private var settings: PassSettings {
        var settings = PassSettings()
        settings.fadeLevel = level
        return settings
    }

    /// The position, fading from the pass's start, or all of it during a hint. The roots and the notes played stay; the
    /// last of those is ringed, or before any, the first to play.
    private func markers(of pass: Int, done: [Attempt], at now: Duration) -> [DrillDisplay.Marker] {
        let position = positions[pass]
        let expected = Self.expectedTimePerNote * order(of: pass).count
        let fade = isHintShown ? NoteFade.none : NoteFade(level: level, expected: expected, start: passStart)
        let played = Set(done.filter { !$0.skipped }.compactMap(\.prompt.target))
        let ringed = done.last?.prompt.target ?? order(of: pass).first
        return position.locations.compactMap { location in
            let name = setup.fretboard.name(at: location, in: position.scale)
            let isRoot = name == position.scale.tonic
            let opacity = isRoot || played.contains(location) || location == ringed ? 1 : fade.opacity(at: now)
            guard opacity > 0 else { return nil }
            return DrillDisplay.Marker(location: location, label: name.description, isAnswer: isRoot, opacity: opacity,
                                       isLastPlayed: location == ringed)
        }
    }

    private func progress(at moment: DrillMoment) -> CircleProgress {
        let attempts = moment.attempts
        let isAnswerable = switch moment.phase {
        case .waiting, .wrong: true
        default: false
        }
        let keys = positions.map(\.scale.key)
        let result = CircleResult(attempts: attempts, count: keys.count).flatMap { $0.isComplete ? $0 : nil }
        let pass = moment.prompt.sweep ?? 0
        var progress = CircleProgress(
            keys: keys, place: pass,
            wrongNotes: attempts.map(\.wrongAnswers.count).reduce(0, +) + (isAnswerable ? moment.wrongAnswers.count : 0),
            skips: attempts.filter(\.skipped).count,
            elapsed: attempts.reduce(.zero) { $0 + ($1.responseTime ?? .zero) },
            runningSince: result == nil && isAnswerable ? moment.promptStart : nil, result: result, best: setup.circleBest)
        if pass + 1 < positions.count {
            progress.nextDetail = "\(positions[pass + 1].name) · \(direction(of: pass + 1).rawValue)"
        }
        return progress
    }
}

extension PassDirection {
    /// "up ↑", "down ↓".
    var text: String { self == .up ? "up ↑" : "down ↓" }
}
