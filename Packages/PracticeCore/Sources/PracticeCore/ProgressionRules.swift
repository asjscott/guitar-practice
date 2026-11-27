import TheoryCore

/// One chord coming up in a progression drill: what the rules choose its expected voicings from.
public struct ChordTurn: Sendable {
    public let fretboard: Fretboard
    public let position: Position
    /// The progression's chords in the key, one per step.
    public let chords: [Triad]
    /// Which of them, from 0.
    public let index: Int
    /// The run's time through it is in, from 0. A time through started again on Resume keeps its number.
    public let timeThrough: Int
    /// This chord's voicings in the position, up the neck.
    public let voicings: [TriadVoicing]
    /// The voicing played for the chord before it; nil for the run's first chord, after Resume, and after a chord
    /// with no voicing played.
    public let previousPlayed: TriadVoicing?
    /// The voicing the app drew for the chord before it; nil for the run's first chord and after Resume.
    public let previousDrawn: TriadVoicing?
    /// The top-note line's note for this chord, in a drill with one (see `ProgressionRules.topNotes`); else nil.
    public let topNote: Pitch?

    public init(fretboard: Fretboard, position: Position, chords: [Triad], index: Int, timeThrough: Int,
                voicings: [TriadVoicing], previousPlayed: TriadVoicing?, previousDrawn: TriadVoicing?,
                topNote: Pitch? = nil) {
        self.fretboard = fretboard
        self.position = position
        self.chords = chords
        self.index = index
        self.timeThrough = timeThrough
        self.voicings = voicings
        self.previousPlayed = previousPlayed
        self.previousDrawn = previousDrawn
        self.topNote = topNote
    }

    public var triad: Triad { chords[index] }
}

/// What a chord expects: the voicings that are clean, and the one drawn while Shown or Faded.
public struct ExpectedVoicings: Hashable, Sendable {
    /// Never empty.
    public let accepted: [TriadVoicing]
    /// One of `accepted`.
    public let drawn: TriadVoicing

    /// Nil when nothing is accepted.
    public init?(accepted: [TriadVoicing], drawn: TriadVoicing?) {
        guard let drawn, !accepted.isEmpty else { return nil }
        precondition(accepted.contains(drawn))
        self.accepted = accepted
        self.drawn = drawn
    }
}

/// What one progression drill expects of each chord; the engine (`ProgressionDrill`) does the rest: windows, scoring,
/// backing, fading and the log.
///
/// To add one: write its rules in its own file, with a `static let` for its kind in an extension of `DrillKind` made
/// with `DrillKind(id:title:instructions:symbol:rules:)`, and add that kind to `DrillKind.all`.
public protocol ProgressionRules: Sendable {
    static var kind: DrillKind { get }

    /// The chord's expected voicings, worked out when it comes up, and again for the neck before then; nil when it
    /// has none (then the drill has nothing to prompt).
    static func expected(for turn: ChordTurn) -> ExpectedVoicings?

    /// A melody on the top notes, one per chord, drawn over the timeline at every fade stage and handed to each
    /// chord's turn; nil (the default) for none.
    static func topNotes(of progression: Progression, in key: Key, position: Position,
                         on fretboard: Fretboard) -> [Pitch]?
}

extension ProgressionRules {
    public static func topNotes(of progression: Progression, in key: Key, position: Position,
                                on fretboard: Fretboard) -> [Pitch]? { nil }
}
