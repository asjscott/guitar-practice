import TheoryCore

extension DrillKind {
    public static let noteCircle = DrillKind(
        id: "noteCircle", module: .notes, title: "Note circle",
        instructions: "Every one of each key’s tonic round the circle of fifths, string 6 to string 1, lowest fret first.",
        symbol: "arrow.clockwise.circle", traits: .goesRoundTheCircle, rules: NoteCircleRules.self)
}

/// Note circle: twelve sweeps, one per key round the circle of fifths from the setup's key, each finding every
/// instance of the key's tonic over frets capo to capo + 12, string 6 first and lowest fret first. A location never
/// times out; a skip leaves the circle not clean. The run ends with the circle. One attempt per location, grouped by
/// sweep, all in circle 0.
public struct NoteCircleRules: DrillRules {
    public static var kind: DrillKind { .noteCircle }

    /// Twelve frets up from the capo.
    static let fretSpan = 12

    public let setup: DrillSetup
    /// The circle, from the setup's key.
    private let keys: [Key]
    /// The current sweep's index in `keys`, and its locations still to prompt.
    private var sweep = -1
    private var queue: [FretboardLocation] = []

    public init(setup: DrillSetup) {
        self.setup = setup
        keys = setup.chosenKey.circleOfFifths
    }

    public mutating func begin() {
        sweep = -1
        queue = []
    }

    public mutating func nextPrompt(after previous: NotePrompt?) -> NotePrompt? {
        while queue.isEmpty {
            guard sweep + 1 < keys.count else { return nil }
            sweep += 1
            queue = locations(in: sweep)
        }
        let location = queue.removeFirst()
        return NotePrompt(name: keys[sweep].tonic, string: location.string, target: location, sweep: sweep)
    }

    /// A sweep's locations, in the order they are found: string 6 first, then by fret.
    private func locations(in sweep: Int) -> [FretboardLocation] {
        let fretboard = setup.fretboard
        let frets = fretboard.capo...min(fretboard.capo + Self.fretSpan, Fretboard.frets.upperBound)
        let tonic = keys[sweep].tonic.pitchClass
        return fretboard.strings.flatMap { fretboard.locations(onString: $0, frets: frets) }
            .filter { fretboard.pitch(at: $0).pitchClass == tonic }
    }

    /// The setup's strings, frets and notes don't apply, and twelve frets always hold every note.
    public var nothingToPromptReason: String? { nil }

    public func judge(_ answer: DrillAnswer, for prompt: NotePrompt) -> DrillJudgement {
        setup.judgeExactPitch(answer, for: prompt)
    }

    public func correctLocations(for prompt: NotePrompt) -> [FretboardLocation] {
        prompt.target.map { [$0] } ?? []
    }

    public func group(for prompt: NotePrompt) -> AttemptGroup? {
        guard let sweep = prompt.sweep else { return nil }
        let locations = locations(in: sweep)
        return AttemptGroup(number: sweep, size: locations.count, place: locations.firstIndex { $0 == prompt.target },
                            circle: 0)
    }

    public var isTimed: Bool { false }

    /// Straight on within a sweep, and into the next with the clock running; the circle's end is held long enough
    /// to read its time.
    public func transition(after attempt: Attempt) -> DrillTransition {
        guard let sweep = attempt.prompt.sweep, attempt.prompt.target == locations(in: sweep).last else {
            return .continuous
        }
        return sweep + 1 < keys.count ? DrillTransition(pause: DrillTiming.correctPause, timesFromLastPrompt: true)
            : DrillTransition(pause: DrillTiming.revealPause, timesFromLastPrompt: false)
    }

    public var resumeRule: DrillResumeRule { .samePrompt(keepingWrongAnswers: true) }

    public func display(of moment: DrillMoment) -> DrillDisplay {
        let prompt = moment.prompt
        let sweep = prompt.sweep ?? 0
        let locations = locations(in: sweep)
        let dealtWith = moment.attempts.filter { $0.prompt.sweep == sweep }
        let isOver = dealtWith.count == locations.count
        let tonic = keys[sweep].tonic.description

        var display = DrillDisplay(standard: moment, in: setup)
        display.headline = "Every \(tonic)"
        display.subline = isOver ? "\(locations.count) of \(locations.count)"
            : "next: \(prompt.stringLabel(in: setup.fretboard.tuning)) · \(dealtWith.count + 1) of \(locations.count)"
        display.highlightedStrings = isOver ? [] : [prompt.string]
        let found = zip(locations, dealtWith).filter { !$1.skipped }.map(\.0)
        display.markers = found.map {
            DrillDisplay.Marker(location: $0, label: tonic, isAnswer: true, isLastPlayed: $0 == dealtWith.last?.location)
        }
        if display.result != .wrong, let last = dealtWith.last, let text = last.rightAnswerText {
            display.feedback = text
        }
        display.circle = progress(at: moment)
        return display
    }

    private func progress(at moment: DrillMoment) -> CircleProgress {
        let attempts = moment.attempts
        let isAnswerable = switch moment.phase {
        case .waiting, .wrong: true
        default: false
        }
        let result = CircleResult(attempts: attempts, count: keys.count).flatMap { $0.isComplete ? $0 : nil }
        let runningSince: Duration? = if result != nil {
            nil
        } else if isAnswerable {
            moment.promptStart
        } else if let start = moment.promptStart, let time = attempts.last?.responseTime {
            // Between sweeps: from the last right note.
            start + time
        } else {
            nil
        }
        return CircleProgress(
            keys: keys, place: moment.prompt.sweep ?? 0,
            wrongNotes: attempts.map(\.wrongAnswers.count).reduce(0, +) + (isAnswerable ? moment.wrongAnswers.count : 0),
            skips: attempts.filter(\.skipped).count,
            elapsed: attempts.reduce(.zero) { $0 + ($1.responseTime ?? .zero) },
            runningSince: runningSince, result: result, best: setup.circleBest)
    }
}
