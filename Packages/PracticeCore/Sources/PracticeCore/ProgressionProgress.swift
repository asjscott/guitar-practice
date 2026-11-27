import TheoryCore

/// Where a progression drill is, for its timeline (see "Progressions (Phase 4)" in docs/ui.md).
public struct ProgressionProgress: Hashable, Sendable {
    /// A chord of the time through.
    public struct Block: Hashable, Sendable {
        /// "Em".
        public var name: String
        /// "vi".
        public var numeral: String
        /// 4 a bar.
        public var beats: Int
        /// Nil until it has been scored.
        public var outcome: ChordOutcome?
    }

    /// This time through's chords, in order.
    public var blocks: [Block]

    /// The chord the playhead is in; nil during the count-in.
    public var current: Int?

    /// Where the playhead is, in beats from this time through's first beat: negative during the count-in.
    public var beat: Double

    /// The run's time through, from 1.
    public var timeThrough: Int

    /// What the chord on the neck is played at.
    public var fadeLevel: FadeLevel

    /// The count-in's beat, 1–4, while it counts in.
    public var countIn: Int?

    /// BPM.
    public var tempo: Int

    /// The frets to zoom the neck to: the position's.
    public var fretWindow: ClosedRange<Int>

    /// A note of the top-note line.
    public struct TopNote: Hashable, Sendable {
        /// Spelled as the chord's tone: "F♯".
        public var name: String
        public var pitch: Pitch
    }

    /// In Target top note, the line's note for each chord, at every fade stage; else nil.
    public var topNotes: [TopNote]?

    /// "3rd time through · Level 2".
    public var timeThroughText: String {
        "\(timeThrough.ordinal) time through · \(fadeLevel)"
    }
}

extension Int {
    /// "1st", "2nd", "3rd", "11th", "22nd".
    public var ordinal: String {
        let suffix = switch (self % 10, self % 100) {
        case (_, 11...13): "th"
        case (1, _): "st"
        case (2, _): "nd"
        case (3, _): "rd"
        default: "th"
        }
        return "\(self)\(suffix)"
    }
}
