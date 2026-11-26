import TheoryCore

/// What a drill is doing now.
public enum DrillPhase: Hashable, Sendable {
    /// Not running: before Start, after Stop, or after an "In order (check)" run ends.
    case idle
    /// A prompt is up; no answer yet.
    case waiting
    /// The last answer was wrong (this pitch class); the prompt stays up.
    case wrong(PitchClass)
    /// The prompt was answered here; the next prompt follows shortly.
    case correct(FretboardLocation)
    /// No right answer in time; the right locations are revealed.
    case timedOut
    /// Paused: the prompt is hidden and the clock stopped.
    case paused
}

/// Something that happens to a drill, with its time on the drill's clock.
public enum DrillEvent: Hashable, Sendable {
    case start(at: Duration)
    case pause(at: Duration)
    case resume(at: Duration)
    case stop(at: Duration)
    /// A played note: its pitch and onset, handled at time `at` (when it was detected).
    case played(Pitch, onset: Duration, at: Duration)
    /// A note name, typed and submitted.
    case typed(NoteName, at: Duration)
    /// Move on from the prompt without a reveal.
    case skip(at: Duration)
    /// R: what it does is up to the drill.
    case `repeat`(at: Duration)
    /// The sounds just asked for were sent to the output, to be heard `latency` later.
    case soundStarted(at: Duration, latency: Duration)
    /// Answers can't be heard until then: the prompt that is up, and any that follows, isn't timed before it.
    /// For drills that can be held (`canHold`); pausing drops it.
    case hold(until: Duration)
    /// The clicks just asked for, as they will be heard.
    case clicksStarted(ClickTrack)
    /// The backing just asked for, as it will be heard: its start may be later than asked. Without sounds the app
    /// plays its beats as clicks, and answers the same.
    case backingStarted(Backing)
    /// H held or let go: the position or voicing is shown meanwhile, and the pass or voicing is hinted. Pausing lets go.
    case hint(isShown: Bool, at: Duration)
    /// What passes are played at, from the next one on.
    case passSettings(PassSettings, at: Duration)
    /// The fade stages reached by now, read again from the log, which has this run's too: from the next pass or voicing on.
    case fadeStages(FadeStages)
    /// The clock moved on; timeouts and the next prompt happen on ticks.
    case tick(at: Duration)
}

/// One tone a drill wants heard.
public struct DrillTone: Hashable, Sendable {
    public let pitch: Pitch
    public let duration: Duration

    public init(pitch: Pitch, duration: Duration) {
        self.pitch = pitch
        self.duration = duration
    }
}

/// Tones to play one after another, starting at a time on the drill's clock.
public struct DrillSoundRequest: Hashable, Sendable {
    public let tones: [DrillTone]
    public let at: Duration

    public init(tones: [DrillTone], at: Duration) {
        self.tones = tones
        self.at = at
    }
}

/// What a drill wants of the metronome.
public enum ClickRequest: Hashable, Sendable {
    /// These clicks from their start on, in place of any others. Answered at once with `DrillEvent.clicksStarted`;
    /// without an answer they are taken to be heard as asked.
    case start(ClickTrack)
    /// None at or after a time.
    case stop(at: Duration)
}

/// What a progression drill wants of the backing player.
public enum BackingRequest: Hashable, Sendable {
    /// This backing from its count-in on, in place of any other. Answered at once with `DrillEvent.backingStarted`;
    /// without an answer it is taken to be heard as asked.
    case start(Backing)
    /// No backing from now on.
    case stop
}

/// The one interface to every drill: a pure state machine driven by events and a clock.
///
/// Free practice and the session player feed it events with times on one clock (played notes' onsets use the
/// same clock). It shows a prompt, checks answers against it, times them, and moves on by itself.
public protocol Drill: Sendable {
    var kind: DrillKind { get }
    var setup: DrillSetup { get }
    var phase: DrillPhase { get }

    /// The prompt on screen; nil when idle or paused.
    var prompt: NotePrompt? { get }

    /// Every attempt in this run, oldest first.
    var attempts: [Attempt] { get }

    /// When the current prompt's timer starts; nil when idle or paused.
    var promptStart: Duration? { get }

    /// How long a prompt waits for an answer.
    var timeLimit: Duration { get }

    /// Time left before the current prompt times out, while it is waiting for an answer.
    func timeRemaining(at now: Duration) -> Duration?

    /// While paused: whether resuming continues the same prompt rather than giving a new one.
    var resumesSamePrompt: Bool { get }

    /// Whether `hold` does anything: the prompt that is up is kept, as it is when resuming.
    var canHold: Bool { get }

    /// Whether the prompt that is up goes on with what an earlier one began, such as a voicing: a chime waits for its
    /// end.
    var isPartWay: Bool { get }

    /// What to show for the current prompt; nil when idle or paused.
    var display: DrillDisplay? { get }

    /// Why Start would show nothing; nil when there is something to prompt.
    var nothingToPromptReason: String? { get }

    mutating func handle(_ event: DrillEvent)

    /// The sounds asked for since the last call: call it after every event. A new prompt, pausing and stopping
    /// drop any not yet taken; the caller also stops what is playing then.
    mutating func takeSounds() -> [DrillSoundRequest]

    /// The clicks asked for since the last call, to be done in order: call it after every event.
    mutating func takeClicks() -> [ClickRequest]

    /// The backing asked for since the last call, to be done in order: call it after every event.
    mutating func takeBacking() -> [BackingRequest]

    /// Between passes, when the last one's last bar ends: a chime waits for that. Nil during a pass, while paused, and in
    /// drills without passes.
    var passEnd: Duration? { get }

    /// What the next pass will be played at, as the tempo ladder moves it; nil in drills without passes.
    var passSettings: PassSettings? { get }

    /// The fade stages reached, this run's included; nil in drills that don't fade.
    var fadeStages: FadeStages? { get }
}

extension Drill {
    public mutating func takeClicks() -> [ClickRequest] { [] }

    public mutating func takeBacking() -> [BackingRequest] { [] }

    public var isPartWay: Bool { false }

    public var passEnd: Duration? { nil }

    public var passSettings: PassSettings? { nil }

    public var fadeStages: FadeStages? { nil }

    /// True from Start until Stop (or the end of an "In order (check)" run), paused included.
    public var isRunning: Bool { phase != .idle }

    /// An "In order (check)" run, which is never logged.
    public var isCheckRun: Bool { kind.offersOrder && setup.options.order == .inOrder }

    /// This run's attempts as the attempt log wants them, oldest first: none from a check run (ADR 0003).
    public var attemptsToLog: [Attempt] { isCheckRun ? [] : attempts }

    public var fretboard: Fretboard { setup.fretboard }
    public var options: DrillOptions { setup.options }

    /// Stats for this run's attempts so far.
    public var stats: RunStats { RunStats(attempts: attempts) }
}
