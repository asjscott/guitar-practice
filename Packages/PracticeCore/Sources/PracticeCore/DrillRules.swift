import TheoryCore

/// What makes one drill different from another. `PromptDrill` does the rest: timing, grace, pauses, skip, pause
/// and the record of attempts.
public protocol DrillRules: Sendable {
    static var kind: DrillKind { get }

    /// With no right answer this long after the timer starts, the attempt times out. Default 10 s.
    static var timeout: Duration { get }

    init(setup: DrillSetup)

    var setup: DrillSetup { get }

    /// A run is starting. Default: nothing.
    mutating func begin()

    /// The next prompt; nil ends the run.
    mutating func nextPrompt(after previous: NotePrompt?) -> NotePrompt?

    func judge(_ answer: DrillAnswer, for prompt: NotePrompt) -> DrillJudgement

    /// Every location that answers a prompt: revealed after a timeout.
    func correctLocations(for prompt: NotePrompt) -> [FretboardLocation]

    /// Why there is nothing to prompt, if so. Default: `setup.nothingToPromptReason`.
    var nothingToPromptReason: String? { get }

    /// Tones to play when a prompt appears, and on a replay. Default: none.
    func sounds(for prompt: NotePrompt) -> [DrillTone]

    /// From the prompt appearing to its timer starting. Default: zero.
    func timerDelay(for prompt: NotePrompt) -> Duration

    /// R was pressed. `.replaySounds` applies only while the prompt awaits an answer. Default: ignored.
    mutating func repeated() -> DrillRepeat

    /// How an answered or timed-out prompt gives way to the next. Default: the standard pauses.
    func transition(after attempt: Attempt) -> DrillTransition

    /// What resuming does when a prompt was waiting. Default: a new prompt.
    var resumeRule: DrillResumeRule { get }

    /// What to show. Default: the note name over its string, wrong notes as "You played G".
    func display(of moment: DrillMoment) -> DrillDisplay
}

/// An answer to a prompt.
public enum DrillAnswer: Hashable, Sendable {
    case played(Pitch)
    case named(NoteName)
}

public enum DrillJudgement: Hashable, Sendable {
    case right(FretboardLocation)
    case wrong(WrongAnswer)
    /// Not an answer to this drill, such as a typed name in a played one.
    case ignored
}

public enum DrillRepeat: Hashable, Sendable {
    case ignored
    /// The prompt's sounds again; its timer runs on.
    case replaySounds
    /// A new prompt, dropping the current one unrecorded.
    case newPrompt
}

/// How one prompt gives way to the next.
public struct DrillTransition: Hashable, Sendable {
    /// How long the answer stays up.
    public let pause: Duration

    /// True when the next prompt's timer runs from this one being dealt with (the right note's onset, or the
    /// moment the time ran out) rather than from the next prompt appearing.
    public let timesFromLastPrompt: Bool

    public init(pause: Duration, timesFromLastPrompt: Bool) {
        self.pause = pause
        self.timesFromLastPrompt = timesFromLastPrompt
    }

    /// Straight on, with no gap in the timing: for locations within a sweep.
    public static let continuous = DrillTransition(pause: .zero, timesFromLastPrompt: true)

    /// The correct pause or the reveal pause, then a fresh timer.
    public static func standard(after attempt: Attempt) -> DrillTransition {
        DrillTransition(pause: attempt.timedOut ? DrillTiming.revealPause : DrillTiming.correctPause,
                        timesFromLastPrompt: false)
    }
}

public enum DrillResumeRule: Hashable, Sendable {
    /// The old prompt is dropped, unrecorded.
    case newPrompt
    /// The same prompt with its timer restarted.
    case samePrompt(keepingWrongAnswers: Bool)
}

extension DrillRules {
    public static var timeout: Duration { .seconds(10) }
    public mutating func begin() {}
    public var nothingToPromptReason: String? { setup.nothingToPromptReason }
    public func sounds(for prompt: NotePrompt) -> [DrillTone] { [] }
    public func timerDelay(for prompt: NotePrompt) -> Duration { .zero }
    public mutating func repeated() -> DrillRepeat { .ignored }
    public func transition(after attempt: Attempt) -> DrillTransition { .standard(after: attempt) }
    public var resumeRule: DrillResumeRule { .newPrompt }
    public func display(of moment: DrillMoment) -> DrillDisplay { DrillDisplay(standard: moment, in: setup) }
}
