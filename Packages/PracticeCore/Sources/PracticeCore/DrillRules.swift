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

    /// The current prompt was answered, timed out or skipped. Default: nothing.
    mutating func dealtWith(_ attempt: Attempt)

    /// The group the current prompt's attempt is in. Default: its sweep, if any.
    func group(for prompt: NotePrompt) -> AttemptGroup?

    /// What else to log about the current prompt. Default: nothing.
    func facts(for prompt: NotePrompt) -> AttemptFacts?

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

    /// Whether the current prompt goes on with what an earlier one began, such as a voicing, so that a chime would
    /// break it up. Default: false.
    var isPartWay: Bool { get }

    /// Whether the current prompt can time out. Default: true.
    var isTimed: Bool { get }

    /// H held or let go; pausing and stopping let go. Default: nothing.
    mutating func hint(isShown: Bool)

    /// The fade levels reached, read again from the log, are set; nil in drills that don't fade. Default: nil.
    var fadeLevels: FadeLevels? { get set }

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

extension DrillSetup {
    /// Judges an answer to a prompt for one location: only its exact pitch is right.
    func judgeExactPitch(_ answer: DrillAnswer, for prompt: NotePrompt) -> DrillJudgement {
        guard case .played(let pitch) = answer, let target = prompt.target else { return .ignored }
        return pitch == fretboard.pitch(at: target) ? .right(target) : .wrong(.pitch(pitch))
    }
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
    /// The rules' next prompt, which goes back to the start of what the old one was part of. To the player it is the
    /// same prompt.
    case samePart
}

extension DrillRules {
    public static var timeout: Duration { .seconds(10) }
    public mutating func begin() {}
    public mutating func dealtWith(_ attempt: Attempt) {}
    public func group(for prompt: NotePrompt) -> AttemptGroup? { nil }
    public func facts(for prompt: NotePrompt) -> AttemptFacts? { nil }
    public var nothingToPromptReason: String? { setup.nothingToPromptReason }
    public func sounds(for prompt: NotePrompt) -> [DrillTone] { [] }
    public func timerDelay(for prompt: NotePrompt) -> Duration { .zero }
    public mutating func repeated() -> DrillRepeat { .ignored }
    public func transition(after attempt: Attempt) -> DrillTransition { .standard(after: attempt) }
    public var resumeRule: DrillResumeRule { .newPrompt }
    public var isPartWay: Bool { false }
    public var isTimed: Bool { true }
    public mutating func hint(isShown: Bool) {}
    public var fadeLevels: FadeLevels? { get { nil } set {} }
    public func display(of moment: DrillMoment) -> DrillDisplay { DrillDisplay(standard: moment, in: setup) }
}
