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

    public var triad: Triad { chords[index] }
}

/// What a chord expects: the voicings that are clean, and the one drawn while Shown or Faded.
public struct ExpectedVoicings: Hashable, Sendable {
    /// Never empty: a progression drill doesn't start unless every chord has a voicing in the position.
    public let accepted: [TriadVoicing]
    /// One of `accepted`.
    public let drawn: TriadVoicing

    public init(accepted: [TriadVoicing], drawn: TriadVoicing) {
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

    /// The chord's expected voicings, worked out when it comes up, and again for the neck before then.
    static func expected(for turn: ChordTurn) -> ExpectedVoicings
}

extension DrillSetup {
    /// Progressions only: the chosen position of the key's scale, or with a theme, the theme's. Nil when it isn't on
    /// the neck.
    public var progressionPosition: Position? {
        if let theme { return theme.position(on: fretboard) }
        let id = options.position
        let positions = fretboard.positions(of: chosenKey.scale, system: options.positionSystem)
        return positions.first { $0.id == id }
            ?? positions.first { $0.system == id.system && $0.number == id.number && $0.octave == 0 }
            ?? positions.first { $0.number == 1 && $0.octave == 0 }
    }

    /// Progressions only: why a run would have nothing to ask; nil when every chord has a voicing in the position.
    public var progressionProblem: String? {
        guard let progression = options.progression else { return "Choose a progression." }
        let key = chosenKey
        guard progression.mode == key.mode else { return "\(progression.name) isn’t in \(key)." }
        guard let position = progressionPosition else { return "The position doesn’t fit the neck." }
        let missing = Set(progression.chords(in: key)).filter { fretboard.voicings(of: $0, in: position).isEmpty }
        guard !missing.isEmpty else { return nil }
        let names = progression.chords(in: key).filter(missing.contains).map(\.shortName).uniqued()
        return "\(names.joined(separator: ", ")) \(names.count == 1 ? "has" : "have") no voicing in the "
            + "\(position.name): choose another position."
    }
}

extension Triad {
    /// "Em", "B♭".
    public var shortName: String { "\(root)\(quality == .minor ? "m" : "")" }
}

extension Array where Element: Hashable {
    /// Without repeats, in order.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
