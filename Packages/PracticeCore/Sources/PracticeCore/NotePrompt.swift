import TheoryCore

/// One Note → play it prompt: a pitch class to play on one string ("F♯ on string 3 (G)").
public struct NotePrompt: Hashable, Sendable {
    public let pitchClass: PitchClass

    /// Internal string index (0 = string 6).
    public let string: Int

    /// The location being checked in "In order (check)"; nil in random order. Any fret on the
    /// string that gives the note still answers the prompt.
    public let target: FretboardLocation?

    public init(pitchClass: PitchClass, string: Int, target: FretboardLocation? = nil) {
        self.pitchClass = pitchClass
        self.string = string
        self.target = target
    }

    /// The note, spelled with sharps since no key applies: "F♯".
    public var noteName: String { pitchClass.sharpName }

    /// The prompted string as shown in a tuning: "string 3 (G)". Ignores any capo.
    public func stringLabel(in tuning: Tuning) -> String { tuning.stringLabel(ofString: string) }

    /// The whole prompt as text: "F♯ on string 3 (G)".
    public func text(in tuning: Tuning) -> String { "\(noteName) on \(stringLabel(in: tuning))" }
}

/// The record of one prompt: whether the first played note was right, the response time,
/// and the wrong notes played before the right one.
public struct Attempt: Hashable, Sendable {
    public let prompt: NotePrompt

    /// True when the first played note answered the prompt. False after a wrong note or a timeout.
    public let firstRight: Bool

    /// Prompt appearing → onset of the right played note; nil = timed out.
    public let responseTime: Duration?

    /// Wrong played notes, in the order they were played.
    public let wrongNotes: [PitchClass]

    /// Where the right note is on the prompted string; nil = timed out.
    public let location: FretboardLocation?

    public init(prompt: NotePrompt, firstRight: Bool, responseTime: Duration?, wrongNotes: [PitchClass], location: FretboardLocation?) {
        self.prompt = prompt
        self.firstRight = firstRight
        self.responseTime = responseTime
        self.wrongNotes = wrongNotes
        self.location = location
    }

    /// True when no right note came within the timeout.
    public var timedOut: Bool { responseTime == nil }
}
