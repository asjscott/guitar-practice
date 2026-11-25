import TheoryCore

/// The engine of the scale drills: passes to the metronome, one note per click, each after a count-in. Timing is logged
/// but never judged. It records one attempt per note; the notes of a pass share a group, and a pass started again is a
/// new one.
///
/// The phase is waiting or wrong from the count-in to the last note: a note played or revealed gives way at once to the
/// next. Then, until the bar ends, it is correct or timed out, as the last note was.
public struct PassDrill<Rules: PassRules>: Drill {
    public private(set) var phase: DrillPhase = .idle
    public private(set) var attempts: [Attempt] = []

    private var rules: Rules
    /// This pass's.
    private var settings: PassSettings
    private var nextSettings: PassSettings

    private var pass: Pass?
    private var group = -1
    /// Which note is up.
    private var place = 0
    /// When the last note was dealt with; nil before the first is.
    private var lastDealtWith: Duration?
    private var wrongSoFar: [Pitch] = []
    /// Whether a hint has been used in this pass.
    private var isHinted = false
    /// H is held.
    private var isHintShown = false
    /// What has been reached, this run's passes included, and what this pass is played at.
    private var fadeStages: FadeStages
    private var fadeStage = FadeStage.shown
    /// Every note has been dealt with.
    private var isOver = false

    /// The clicks as they are heard, as far as is known, and which of them the count-in starts on (once this pass is
    /// over, the next one's).
    private var track: ClickTrack
    private var countInClick = 0
    /// Once this pass is over: when its last bar ends.
    private var barEnd: Duration = .zero
    private var pendingClicks: [ClickRequest] = []
    private var now: Duration = .zero

    public init(setup: DrillSetup) {
        rules = Rules(setup: setup)
        settings = setup.options.pass
        nextSettings = settings
        fadeStages = setup.fadeStages
        track = ClickTrack(meter: settings.meter, bpm: settings.tempo, start: .zero)
    }

    // MARK: - State

    public var kind: DrillKind { Rules.kind }
    public var setup: DrillSetup { rules.setup }
    public var timeLimit: Duration { .seconds(5) }
    public var nothingToPromptReason: String? { rules.nothingToPromptReason }
    /// Between passes: the next count-in is put off.
    public var canHold: Bool { true }
    public var resumesSamePrompt: Bool { phase == .paused && !isOver }

    /// The note that is up; once the pass is over, its last.
    public var prompt: NotePrompt? {
        guard isRunning, phase != .paused, let pass, let location = expected else { return nil }
        return NotePrompt(name: fretboard.name(at: location, in: pass.scale), string: location.string, target: location)
    }

    public var promptStart: Duration? { isRunning && phase != .paused ? timerStart : nil }

    public func timeRemaining(at now: Duration) -> Duration? {
        isAnswerable ? min(timeLimit, max(.zero, timeLimit - (now - timerStart))) : nil
    }

    public mutating func takeSounds() -> [DrillSoundRequest] { [] }

    public mutating func takeClicks() -> [ClickRequest] {
        defer { pendingClicks = [] }
        return pendingClicks
    }

    private var isAnswerable: Bool {
        switch phase {
        case .waiting, .wrong: true
        default: false
        }
    }

    /// This pass's so far.
    private var passAttempts: [Attempt] { attempts.filter { $0.group?.number == group } }

    private var expected: FretboardLocation? {
        pass.map { $0.locations[min(place, $0.locations.count - 1)] }
    }

    private var countInStart: Duration { track.time(ofClick: countInClick) }
    private var beatOne: Duration { track.time(ofClick: countInClick + settings.meter.signature.countInClicks) }
    private var timerStart: Duration { lastDealtWith ?? beatOne }

    // MARK: - Events

    public mutating func handle(_ event: DrillEvent) {
        switch event {
        case .start(let now):
            guard !isRunning else { return }
            attempts = []
            rules.begin()
            beginNext(at: now)
        case .pause(let now):
            advance(to: now)
            guard isRunning, phase != .paused else { return }
            phase = .paused
            isHintShown = false
            pendingClicks = [.stop(at: now)]
        case .resume(let now):
            guard phase == .paused else { return }
            isOver ? beginNext(at: now) : beginAgain(at: now)
        case .stop(let now):
            stop(at: now)
        case .played(let pitch, let onset, let now):
            // Up to the onset with no grace: a note played after the timeout doesn't count.
            advance(to: onset, grace: .zero)
            judge(pitch, onset: onset)
            advance(to: now)
        case .skip(let now):
            advance(to: now)
            guard isRunning, phase != .paused else { return }
            if isAnswerable { record(.skipped) }
            beginNext(at: now)
        case .repeat(let now):
            advance(to: now)
            guard isRunning, phase != .paused else { return }
            beginAgain(at: now)
        case .hint(let isShown, let now):
            advance(to: now)
            guard isRunning, phase != .paused else { return }
            isHintShown = isShown
            if isShown, !isOver { isHinted = true }
        case .clicksStarted(let heard):
            track = heard
        case .passSettings(let new, let now):
            advance(to: now)
            nextSettings = new
            if isOver, phase != .paused { askForNextClicks() }
        case .hold(let end):
            if isOver, phase != .paused, end > countInStart { askForClicks(from: end) }
        case .tick(let now):
            advance(to: now)
        case .typed, .soundStarted:
            break
        }
    }

    // MARK: - Passes

    /// The next pass, with new clicks.
    private mutating func beginNext(at now: Duration) {
        guard let next = rules.nextPass() else { return stop(at: now) }
        begin(next, at: now)
    }

    /// The same pass, with new clicks.
    private mutating func beginAgain(at now: Duration) {
        if let pass { begin(pass, at: now) }
    }

    private mutating func begin(_ pass: Pass, at now: Duration) {
        self.now = max(self.now, now)
        show(pass)
        track = ClickTrack(meter: settings.meter, bpm: settings.tempo, start: now)
        countInClick = 0
        pendingClicks = [.start(track)]
    }

    private mutating func show(_ pass: Pass) {
        self.pass = pass
        settings = nextSettings
        group += 1
        place = 0
        lastDealtWith = nil
        wrongSoFar = []
        isHinted = isHintShown
        fadeStage = settings.fadeStage ?? fadeStages.stage(
            of: FadeStages.Subject(tuning: fretboard.tuning, scaleKind: pass.scale.kind, position: pass.position.id))
        isOver = false
        phase = .waiting
    }

    private mutating func stop(at now: Duration) {
        guard isRunning else { return }
        phase = .idle
        pass = nil
        isHintShown = false
        isOver = false
        pendingClicks = [.stop(at: now)]
    }

    /// The last note was dealt with: the click runs to the end of the bar that note's nearest click is in.
    private mutating func end(at time: Duration) {
        isOver = true
        fadeStages.add([PassResult(attempts: passAttempts)], in: fretboard.tuning)
        let beats = track.meter.signature.beats
        countInClick = (track.nearestClick(to: time) / beats + 1) * beats
        while countInStart <= now { countInClick += beats }
        barEnd = countInStart
        askForNextClicks()
    }

    /// The next count-in goes on with the same clicks, unless the settings have changed.
    private mutating func askForNextClicks() {
        if nextSettings.meter != track.meter || nextSettings.tempo != track.bpm {
            askForClicks(from: max(barEnd, countInStart))
        }
    }

    private mutating func askForClicks(from start: Duration) {
        track = ClickTrack(meter: nextSettings.meter, bpm: nextSettings.tempo, start: start)
        countInClick = 0
        pendingClicks += [.stop(at: barEnd), .start(track)]
    }

    /// Moves the clock to `now`: due timeouts (once `grace` past them), then the next pass.
    private mutating func advance(to now: Duration, grace: Duration = DrillTiming.detectionGrace) {
        self.now = max(self.now, now)
        while isAnswerable, now >= timerStart + timeLimit + grace {
            let end = timerStart + timeLimit
            record(.timedOut)
            moveOn(at: end, phaseAfterLast: .timedOut)
        }
        if isOver, phase != .paused, now >= countInStart {
            guard let next = rules.nextPass() else { return stop(at: now) }
            show(next)
        }
    }

    // MARK: - Notes

    private mutating func judge(_ pitch: Pitch, onset: Duration) {
        guard isAnswerable, let location = expected else { return }
        let isRight = fretboard.pitch(at: location) == pitch
        if place == 0, onset < beatOne {
            let halfBeat = Duration.seconds(30) / settings.tempo
            guard isRight, onset >= beatOne - halfBeat else { return }
        } else if onset < timerStart {
            return
        }
        if isRight {
            record(.answered, onset: onset, location: location)
            moveOn(at: onset, phaseAfterLast: .correct(location))
        } else {
            wrongSoFar.append(pitch)
            phase = .wrong(pitch.pitchClass)
        }
    }

    private mutating func record(_ outcome: Attempt.Outcome, onset: Duration? = nil, location: FretboardLocation? = nil) {
        guard let pass, let prompt else { return }
        let signature = settings.meter.signature
        let facts = PassFacts(scale: pass.scale, position: pass.position.id, startDegree: pass.startDegree,
                              tempo: settings.tempo, beatsPerBar: signature.beats, beatUnit: signature.unit,
                              fadeStage: fadeStage, hinted: isHinted,
                              clickOffset: onset.map { $0 - track.time(ofClick: track.nearestClick(to: $0)) })
        attempts.append(Attempt(prompt: prompt, outcome: outcome, responseTime: onset.map { max(.zero, $0 - timerStart) },
                                wrongAnswers: wrongSoFar.map { .pitch($0) }, location: location,
                                group: AttemptGroup(number: group, size: pass.locations.count, place: place),
                                facts: .pass(facts)))
    }

    /// The note that was up is dealt with.
    private mutating func moveOn(at time: Duration, phaseAfterLast: DrillPhase) {
        lastDealtWith = time
        wrongSoFar = []
        place += 1
        if place == pass?.locations.count {
            phase = phaseAfterLast
            end(at: time)
        } else {
            phase = .waiting
        }
    }

    // MARK: - Display

    public var display: DrillDisplay? {
        guard isRunning, phase != .paused, let pass else { return nil }
        let done = passAttempts
        let (result, feedback) = resultAndFeedback(after: done, in: pass)
        var display = DrillDisplay(headline: rules.headline(of: pass), subline: pass.position.name, feedback: feedback,
                                   result: result, markers: markers(of: pass, last: done.last?.prompt.target))
        display.pass = PassProgress(notes: line(of: pass, done: done), countIn: countInBeat, settings: settings)
        return display
    }

    private var isCountingIn: Bool { isAnswerable && place == 0 && now < beatOne }

    private var countInBeat: Int? {
        guard isCountingIn, now >= countInStart else { return nil }
        return track.click(track.lastClick(by: now)).beat
    }

    private func resultAndFeedback(after done: [Attempt], in pass: Pass) -> (DrillDisplay.Result, String) {
        switch phase {
        case .wrong(let played):
            let isAnotherOctave = played == prompt?.pitchClass
            return (.wrong, "You played \(pass.scale.spell(played))" + (isAnotherOctave ? ", in another octave" : ""))
        case .waiting:
            if isCountingIn { return (.waiting, passes.last(where: \.isComplete)?.lastPassText ?? "Pick every note") }
            guard let last = done.last, last.timedOut else { return (.waiting, "Listening…") }
            return (.timedOut, "Time’s up: it was \(last.prompt.noteName)")
        case .correct, .timedOut, .idle, .paused:
            let result = PassResult(attempts: done)
            return (result.isClean ? .right : phase == .timedOut ? .timedOut : .waiting, result.text)
        }
    }

    /// As much of the position as the fade stage shows, or all of it during a hint; the last note played or revealed is
    /// ringed.
    private func markers(of pass: Pass, last: FretboardLocation?) -> [DrillDisplay.Marker] {
        let stage = isHintShown ? .shown : fadeStage
        return pass.position.locations.compactMap { location in
            let name = fretboard.name(at: location, in: pass.scale)
            let isRoot = name == pass.scale.tonic, isLast = location == last
            guard stage != .hidden || isRoot || isLast else { return nil }
            let isFaint = stage != .shown && !isLast
            return DrillDisplay.Marker(location: location, label: isFaint ? "" : name.description, isAnswer: isRoot,
                                       isFaint: isFaint, isLastPlayed: isLast)
        }
    }

    private func line(of pass: Pass, done: [Attempt]) -> [PassProgress.Note] {
        let pitches = pass.locations.map { fretboard.pitch(at: $0).midi }
        let lowest = pitches.min() ?? 0
        let range = max(1, (pitches.max() ?? 0) - lowest)
        return pitches.enumerated().map { index, pitch in
            let state: DrillDisplay.Chip.State = if index < done.count { done[index].timedOut ? .timedOut : .found }
                else { index == place ? .current : .waiting }
            return PassProgress.Note(height: Double(pitch - lowest) / Double(range), state: state)
        }
    }
}
