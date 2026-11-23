import TheoryCore

/// Timing every drill shares.
public enum DrillTiming {
    /// How long past the timeout a tick waits before timing the attempt out. A played note reaches the
    /// engine about 130 ms after its onset (detection, plus the hop to the main actor), so without this a
    /// tick at 10.0 s would time out a right note played at 9.9 s that is still being detected. The grace
    /// only delays ticks: a played note still has to have its onset before the timeout to count, and the
    /// countdown still reaches zero at the timeout.
    public static let detectionGrace: Duration = .milliseconds(200)

    /// How long a right answer stays lit before the next prompt.
    public static let correctPause: Duration = .milliseconds(400)

    /// How long a timeout's revealed locations stay up before the next prompt.
    public static let revealPause: Duration = .milliseconds(1800)
}

/// The drill engine: runs one drill's rules, and does everything drills share.
public struct PromptDrill<Rules: DrillRules>: Drill {
    public static var timeout: Duration { Rules.timeout }
    public static var detectionGrace: Duration { DrillTiming.detectionGrace }
    public static var correctPause: Duration { DrillTiming.correctPause }
    public static var revealPause: Duration { DrillTiming.revealPause }

    public private(set) var phase: DrillPhase = .idle
    public private(set) var attempts: [Attempt] = []

    private var rules: Rules
    private var current: NotePrompt?
    private var timerStart: Duration?
    private var wrongSoFar: [WrongAnswer] = []
    /// The same answers as they were given.
    private var rawWrongSoFar: [DrillAnswer] = []
    /// After a prompt is dealt with: when the next appears, and when its timer starts if not then.
    private var next: (at: Duration, timerStart: Duration?)?
    private var wasAnswerableBeforePause = false
    private var pendingSounds: [DrillSoundRequest] = []

    public init(setup: DrillSetup) {
        rules = Rules(setup: setup)
    }

    public init(fretboard: Fretboard, options: DrillOptions, seed: UInt64) {
        self.init(setup: DrillSetup(fretboard: fretboard, options: options, seed: seed))
    }

    // MARK: - State

    public var kind: DrillKind { Rules.kind }
    public var setup: DrillSetup { rules.setup }
    public var timeLimit: Duration { Rules.timeout }
    public var nothingToPromptReason: String? { rules.nothingToPromptReason }

    public var prompt: NotePrompt? { phase == .paused ? nil : current }
    public var promptStart: Duration? { phase == .paused ? nil : timerStart }

    /// The location to light on a right answer.
    public var litLocation: FretboardLocation? {
        if case .correct(let location) = phase { location } else { nil }
    }

    /// Every location that answers the current prompt.
    public var correctLocations: [FretboardLocation] {
        prompt.map { rules.correctLocations(for: $0) } ?? []
    }

    /// The locations revealed after a timeout; empty otherwise.
    public var revealedLocations: [FretboardLocation] {
        phase == .timedOut ? correctLocations : []
    }

    public func timeRemaining(at now: Duration) -> Duration? {
        guard isAnswerable, let timerStart else { return nil }
        return min(timeLimit, max(.zero, timeLimit - (now - timerStart)))
    }

    public var display: DrillDisplay? {
        guard isRunning, let prompt else { return nil }
        return rules.display(of: DrillMoment(prompt: prompt, phase: phase, wrongAnswers: wrongSoFar,
                                             attempts: attempts, correctLocations: correctLocations))
    }

    public mutating func takeSounds() -> [DrillSoundRequest] {
        defer { pendingSounds = [] }
        return pendingSounds
    }

    // MARK: - Events

    public mutating func handle(_ event: DrillEvent) {
        switch event {
        case .start(let now):
            start(at: now)
        case .pause(let now):
            pause(at: now)
        case .resume(let now):
            resume(at: now)
        case .stop:
            stop()
        case .played(let pitch, let onset, let now):
            answer(.played(pitch), madeAt: onset, at: now)
        case .typed(let name, let now):
            answer(.named(name), madeAt: now, at: now)
        case .skip(let now):
            skip(at: now)
        case .repeat(let now):
            repeatPrompt(at: now)
        case .tick(let now):
            advance(to: now)
        }
    }

    private var isAnswerable: Bool {
        switch phase {
        case .waiting, .wrong: true
        default: false
        }
    }

    private mutating func start(at now: Duration) {
        guard !isRunning else { return }
        attempts = []
        rules.begin()
        showNextPrompt(at: now)
    }

    private mutating func pause(at now: Duration) {
        advance(to: now)
        guard isRunning, phase != .paused else { return }
        wasAnswerableBeforePause = isAnswerable
        phase = .paused
        pendingSounds = []
    }

    private mutating func resume(at now: Duration) {
        guard phase == .paused else { return }
        guard wasAnswerableBeforePause, let current, case .samePrompt(let keepsWrong) = rules.resumeRule else {
            return showNextPrompt(at: now)
        }
        let kept = keepsWrong ? wrongSoFar : []
        let keptRaw = keepsWrong ? rawWrongSoFar : []
        show(current, at: now)
        wrongSoFar = kept
        rawWrongSoFar = keptRaw
        if let last = kept.last { phase = .wrong(last.pitchClass) }
    }

    private mutating func stop() {
        phase = .idle
        current = nil
        timerStart = nil
        next = nil
        wrongSoFar = []
        rawWrongSoFar = []
        pendingSounds = []
    }

    private mutating func skip(at now: Duration) {
        advance(to: now)
        guard isRunning, phase != .paused, let current else { return }
        if isAnswerable {
            attempts.append(Attempt(prompt: current, outcome: .skipped, wrongAnswers: wrongSoFar,
                                    rawWrongAnswers: rawWrongSoFar))
        }
        showNextPrompt(at: now)
    }

    private mutating func repeatPrompt(at now: Duration) {
        advance(to: now)
        guard isRunning, phase != .paused, let current else { return }
        switch rules.repeated() {
        case .ignored: break
        case .replaySounds: if isAnswerable { requestSounds(for: current, at: now) }
        case .newPrompt: showNextPrompt(at: now)
        }
    }

    private mutating func answer(_ answer: DrillAnswer, madeAt: Duration, at now: Duration) {
        // Up to the answer with no grace: one given after the timeout doesn't count.
        advance(to: madeAt, grace: .zero)
        judge(answer, madeAt: madeAt, at: max(madeAt, now))
        advance(to: now)
    }

    private mutating func judge(_ answer: DrillAnswer, madeAt: Duration, at now: Duration) {
        guard isAnswerable, let current, let timerStart, madeAt >= timerStart else { return }
        switch rules.judge(answer, for: current) {
        case .right(let location):
            let attempt = Attempt(prompt: current, outcome: .answered, responseTime: madeAt - timerStart,
                                  wrongAnswers: wrongSoFar, rawWrongAnswers: rawWrongSoFar, location: location)
            attempts.append(attempt)
            phase = .correct(location)
            let transition = rules.transition(after: attempt)
            next = (now + transition.pause, transition.timesFromLastPrompt ? madeAt : nil)
        case .wrong(let wrong):
            wrongSoFar.append(wrong)
            rawWrongSoFar.append(answer)
            phase = .wrong(wrong.pitchClass)
        case .ignored:
            break
        }
    }

    /// Moves the clock to `now`: a due timeout (once `grace` past the timeout), then a due next prompt.
    private mutating func advance(to now: Duration, grace: Duration = DrillTiming.detectionGrace) {
        if isAnswerable, let current, let timerStart, now - timerStart >= timeLimit + grace {
            let attempt = Attempt(prompt: current, outcome: .timedOut, wrongAnswers: wrongSoFar,
                                  rawWrongAnswers: rawWrongSoFar)
            attempts.append(attempt)
            phase = .timedOut
            let transition = rules.transition(after: attempt)
            let end = timerStart + timeLimit
            next = transition.timesFromLastPrompt ? (end + transition.pause, end)
                : (end + DrillTiming.detectionGrace + transition.pause, nil)
        }
        if phase != .paused, let next, now >= next.at {
            showNextPrompt(at: now, timerStart: next.timerStart)
        }
    }

    private mutating func showNextPrompt(at now: Duration, timerStart: Duration? = nil) {
        guard let prompt = rules.nextPrompt(after: current) else { return stop() }
        show(prompt, at: now, timerStart: timerStart)
    }

    private mutating func show(_ prompt: NotePrompt, at now: Duration, timerStart: Duration? = nil) {
        current = prompt
        self.timerStart = timerStart ?? now + rules.timerDelay(for: prompt)
        next = nil
        wrongSoFar = []
        rawWrongSoFar = []
        phase = .waiting
        pendingSounds = []
        requestSounds(for: prompt, at: now)
    }

    private mutating func requestSounds(for prompt: NotePrompt, at now: Duration) {
        let tones = rules.sounds(for: prompt)
        if !tones.isEmpty { pendingSounds.append(DrillSoundRequest(tones: tones, at: now)) }
    }
}
