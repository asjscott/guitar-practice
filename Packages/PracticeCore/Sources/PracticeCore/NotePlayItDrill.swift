import TheoryCore

/// The Note → play it drill engine: a pure state machine driven by events and a clock.
///
/// Feed it events with times on one clock (the played notes' onsets use the same clock).
/// It shows a prompt, checks played notes against it, times them, and moves on by itself.
/// It asks TheoryCore which fretboard locations answer a prompt; it does no note maths.
public struct NotePlayItDrill: Sendable {
    /// With no right note this long after a prompt appears, the attempt times out.
    public static let timeout: Duration = .seconds(10)

    /// How long a right answer stays lit before the next prompt.
    public static let correctPause: Duration = .milliseconds(400)

    /// How long a timeout's revealed locations stay up before the next prompt.
    public static let revealPause: Duration = .milliseconds(1800)

    /// What the drill is doing now.
    public enum Phase: Hashable, Sendable {
        /// Not running: before Start, after Stop, or after an "In order (check)" run ends.
        case idle
        /// A prompt is up; no note played yet.
        case waiting
        /// The last played note was wrong (this pitch class); the prompt stays up.
        case wrong(PitchClass)
        /// The prompt was answered here; the next prompt follows shortly.
        case correct(FretboardLocation)
        /// No right note in time; the right locations are revealed.
        case timedOut
        /// Paused; the clock is stopped.
        case paused
    }

    /// Something that happens to the drill, with its time on the drill's clock.
    public enum Event: Hashable, Sendable {
        case start(at: Duration)
        case pause(at: Duration)
        case resume(at: Duration)
        case stop(at: Duration)
        /// A played note: its pitch and onset, handled at time `at` (when it was detected).
        case played(Pitch, onset: Duration, at: Duration)
        /// The clock moved on; timeouts and the next prompt happen on ticks.
        case tick(at: Duration)
    }

    public let fretboard: Fretboard
    public let options: NotePlayItOptions

    public private(set) var phase: Phase = .idle

    /// The prompt on screen, or nil when idle.
    public private(set) var prompt: NotePrompt?

    /// Every attempt in this run, oldest first.
    public private(set) var attempts: [Attempt] = []

    /// When the current prompt appeared (or its timer restarted on resume).
    public private(set) var promptStart: Duration?

    private var wrongSoFar: [PitchClass] = []
    private var nextPromptAt: Duration?
    private var phaseBeforePause: Phase?
    private var queue: [NotePrompt] = []
    private var random: SplitMix64

    public init(fretboard: Fretboard, options: NotePlayItOptions, seed: UInt64) {
        self.fretboard = fretboard
        self.options = options
        self.random = SplitMix64(seed: seed)
    }

    /// True from Start until Stop (or the end of an "In order (check)" run), paused included.
    public var isRunning: Bool { phase != .idle }

    /// The location to light on a right answer.
    public var litLocation: FretboardLocation? {
        if case .correct(let location) = phase { location } else { nil }
    }

    /// Every location that answers the current prompt: on the prompted string, in the fret
    /// range, at or above the capo.
    public var correctLocations: [FretboardLocation] {
        guard let prompt else { return [] }
        return fretboard.locations(of: prompt.pitchClass, onString: prompt.string, frets: options.frets)
    }

    /// The locations revealed after a timeout; empty otherwise.
    public var revealedLocations: [FretboardLocation] {
        phase == .timedOut ? correctLocations : []
    }

    /// Time left before the current prompt times out, while it is waiting for an answer.
    public func timeRemaining(at now: Duration) -> Duration? {
        guard isAnswerable, let promptStart else { return nil }
        return max(.zero, Self.timeout - (now - promptStart))
    }

    /// Handles one event.
    public mutating func handle(_ event: Event) {
        switch event {
        case .start(let now):
            start(at: now)
        case .pause(let now):
            advance(to: now)
            guard isRunning, phase != .paused else { return }
            phaseBeforePause = phase
            phase = .paused
        case .resume(let now):
            guard phase == .paused, let before = phaseBeforePause else { return }
            phaseBeforePause = nil
            switch before {
            case .waiting, .wrong:
                phase = before
                promptStart = now
            default:
                showNextPrompt(at: now)
            }
        case .stop:
            stop()
        case .played(let pitch, let onset, let now):
            advance(to: onset)
            play(pitch, onset: onset, at: max(onset, now))
            advance(to: now)
        case .tick(let now):
            advance(to: now)
        }
    }

    // MARK: - Running

    private var isAnswerable: Bool {
        switch phase {
        case .waiting, .wrong: true
        default: false
        }
    }

    private mutating func start(at now: Duration) {
        guard !isRunning else { return }
        attempts = []
        prompt = nil
        queue = options.order == .inOrder ? checkPrompts : []
        showNextPrompt(at: now)
    }

    private mutating func stop() {
        phase = .idle
        prompt = nil
        promptStart = nil
        nextPromptAt = nil
        phaseBeforePause = nil
        wrongSoFar = []
        queue = []
    }

    private mutating func showNextPrompt(at now: Duration) {
        guard let next = nextPrompt() else { return stop() }
        prompt = next
        promptStart = now
        nextPromptAt = nil
        wrongSoFar = []
        phase = .waiting
    }

    private mutating func play(_ pitch: Pitch, onset: Duration, at now: Duration) {
        guard isAnswerable, let prompt, let promptStart, onset >= promptStart else { return }
        if pitch.pitchClass == prompt.pitchClass,
           let location = fretboard.location(of: pitch, onString: prompt.string, frets: options.frets) {
            attempts.append(Attempt(prompt: prompt, firstRight: wrongSoFar.isEmpty, responseTime: onset - promptStart,
                                    wrongNotes: wrongSoFar, location: location))
            phase = .correct(location)
            nextPromptAt = now + Self.correctPause
        } else {
            wrongSoFar.append(pitch.pitchClass)
            phase = .wrong(pitch.pitchClass)
        }
    }

    /// Moves the clock to `now`: a due timeout, then a due next prompt.
    private mutating func advance(to now: Duration) {
        if isAnswerable, let prompt, let promptStart, now - promptStart >= Self.timeout {
            attempts.append(Attempt(prompt: prompt, firstRight: false, responseTime: nil,
                                    wrongNotes: wrongSoFar, location: nil))
            phase = .timedOut
            nextPromptAt = promptStart + Self.timeout + Self.revealPause
        }
        if phase != .paused, let nextPromptAt, now >= nextPromptAt {
            showNextPrompt(at: now)
        }
    }

    // MARK: - Choosing prompts

    /// The locations the run can prompt: included strings, fret range, capo, note filter.
    private var candidateLocations: [FretboardLocation] {
        fretboard.strings
            .filter { options.strings?.contains($0) ?? true }
            .flatMap { fretboard.locations(onString: $0, frets: options.frets) }
            .filter { options.notes == .all || fretboard.pitch(at: $0).pitchClass.isNatural }
    }

    /// "In order (check)": one prompt per location, string 6 first, fret by fret.
    private var checkPrompts: [NotePrompt] {
        candidateLocations.map {
            NotePrompt(pitchClass: fretboard.pitch(at: $0).pitchClass, string: $0.string, target: $0)
        }
    }

    /// Random order: each distinct (note, string) once.
    private var randomPrompts: [NotePrompt] {
        var seen = Set<NotePrompt>()
        return candidateLocations
            .map { NotePrompt(pitchClass: fretboard.pitch(at: $0).pitchClass, string: $0.string) }
            .filter { seen.insert($0).inserted }
    }

    private mutating func nextPrompt() -> NotePrompt? {
        switch options.order {
        case .inOrder:
            return queue.isEmpty ? nil : queue.removeFirst()
        case .random:
            let all = randomPrompts
            let choices = all.count > 1 ? all.filter { $0 != prompt } : all
            guard !choices.isEmpty else { return nil }
            return choices[Int(random.next() % UInt64(choices.count))]
        }
    }
}

/// A small seeded random number generator, so a seed always gives the same run.
struct SplitMix64: Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
