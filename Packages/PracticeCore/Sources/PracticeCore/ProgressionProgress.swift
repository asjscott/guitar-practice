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

    public var fadeStage: FadeStage

    /// The count-in's beat, 1–4, while it counts in.
    public var countIn: Int?

    /// BPM.
    public var tempo: Int

    /// The frets to zoom the neck to: the position's.
    public var fretWindow: ClosedRange<Int>

    /// "3rd time through · Faded".
    public var timeThroughText: String {
        "\(timeThrough.ordinal) time through · \(fadeStage.title)"
    }
}

extension FadeStage {
    /// "Shown".
    public var title: String {
        switch self {
        case .shown: "Shown"
        case .faded: "Faded"
        case .hidden: "Hidden"
        }
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
