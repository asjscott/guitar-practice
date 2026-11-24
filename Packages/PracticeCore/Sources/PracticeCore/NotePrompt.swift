import TheoryCore

/// One prompt: a note on one string ("F♯ on string 3 (G)"), and the exact location where a drill has one.
public struct NotePrompt: Hashable, Sendable {
    /// The note as spelled to the player.
    public let name: NoteName

    /// Internal string index (0 = string 6).
    public let string: Int

    /// The location asked for, in drills that ask for one; nil when any fret on the string that gives the note
    /// will do. In Note → play it, "In order (check)" sets it but any such fret still answers.
    public let target: FretboardLocation?

    /// Which of the run's sweeps this is in, in All instances; nil in other drills. The log groups attempts by it.
    public let sweep: Int?

    public init(name: NoteName, string: Int, target: FretboardLocation? = nil, sweep: Int? = nil) {
        self.name = name
        self.string = string
        self.target = target
        self.sweep = sweep
    }

    /// Spelled with sharps, since no key applies.
    public init(pitchClass: PitchClass, string: Int, target: FretboardLocation? = nil) {
        self.init(name: NoteName(sharpSpelling: pitchClass), string: string, target: target)
    }

    public var pitchClass: PitchClass { name.pitchClass }

    /// The note as text: "F♯".
    public var noteName: String { name.description }

    /// The prompted string as shown in a tuning: "string 3 (G)". Ignores any capo.
    public func stringLabel(in tuning: Tuning) -> String { tuning.stringLabel(ofString: string) }

    /// The whole prompt as text: "F♯ on string 3 (G)".
    public func text(in tuning: Tuning) -> String { "\(noteName) on \(stringLabel(in: tuning))" }
}
