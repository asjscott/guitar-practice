import TheoryCore

/// A wrong answer, as the drill took it.
public enum WrongAnswer: Hashable, Sendable {
    /// A played note, where the octave isn't recorded.
    case note(PitchClass)
    /// A played note, with its octave.
    case pitch(Pitch)
    /// A typed note name.
    case name(NoteName)

    public var pitchClass: PitchClass {
        switch self {
        case .note(let pitchClass): pitchClass
        case .pitch(let pitch): pitch.pitchClass
        case .name(let name): name.pitchClass
        }
    }

    /// What was played or typed; nil when the octave isn't recorded.
    public var raw: DrillAnswer? {
        switch self {
        case .note: nil
        case .pitch(let pitch): .played(pitch)
        case .name(let name): .named(name)
        }
    }

    /// "G♯"; a typed name as it was typed.
    public var text: String {
        if case .name(let name) = self { name.description } else { pitchClass.sharpName }
    }
}

/// The record of one prompt's outcome: response time, and the wrong answers before the right one.
public struct Attempt: Hashable, Sendable {
    /// The raw values are saved in the attempt log: never change them.
    public enum Outcome: String, Hashable, Sendable {
        case answered, timedOut, skipped
    }

    public let prompt: NotePrompt
    public let outcome: Outcome

    /// True when the first answer was right. False after a wrong answer, a timeout or a skip.
    public let firstRight: Bool

    /// The timer starting → onset of the right played note, or the right name submitted; nil unless answered.
    public let responseTime: Duration?

    /// In the order they were given.
    public let wrongAnswers: [WrongAnswer]

    /// The same wrong answers as they were given, for the attempt log (ADR 0003): played ones with their octave,
    /// whatever the drill made of them. Not part of `==`.
    public let rawWrongAnswers: [DrillAnswer]

    /// Where the right answer is on the prompted string; nil unless answered.
    public let location: FretboardLocation?

    /// `rawWrongAnswers` is worked out from `wrongAnswers` unless given. `responseTime` and `location` are both given when answered, and neither otherwise.
    public init(prompt: NotePrompt, outcome: Outcome, responseTime: Duration? = nil,
                wrongAnswers: [WrongAnswer] = [], rawWrongAnswers: [DrillAnswer]? = nil,
                location: FretboardLocation? = nil) {
        self.prompt = prompt
        self.outcome = outcome
        self.firstRight = outcome == .answered && wrongAnswers.isEmpty
        self.responseTime = responseTime
        self.wrongAnswers = wrongAnswers
        self.rawWrongAnswers = rawWrongAnswers ?? wrongAnswers.compactMap(\.raw)
        self.location = location
    }

    /// An answered or timed-out (no response time) attempt with played wrong notes.
    public init(prompt: NotePrompt, firstRight: Bool, responseTime: Duration?, wrongNotes: [PitchClass], location: FretboardLocation?) {
        self.init(prompt: prompt, outcome: responseTime == nil ? .timedOut : .answered, responseTime: responseTime,
                  wrongAnswers: wrongNotes.map { .note($0) }, location: location)
    }

    /// The wrong answers' pitch classes.
    public var wrongNotes: [PitchClass] { wrongAnswers.map(\.pitchClass) }

    /// True when no right answer came within the timeout.
    public var timedOut: Bool { outcome == .timedOut }

    public var skipped: Bool { outcome == .skipped }

    public static func == (a: Attempt, b: Attempt) -> Bool { a.compared == b.compared }
    public func hash(into hasher: inout Hasher) { hasher.combine(compared) }

    /// Everything but `rawWrongAnswers` (`firstRight` follows from the rest).
    private var compared: Compared {
        Compared(prompt: prompt, outcome: outcome, responseTime: responseTime, wrongAnswers: wrongAnswers, location: location)
    }

    private struct Compared: Hashable {
        let prompt: NotePrompt
        let outcome: Outcome
        let responseTime: Duration?
        let wrongAnswers: [WrongAnswer]
        let location: FretboardLocation?
    }
}
