import TheoryCore

extension DrillKind {
    public static let nearestVoicing = DrillKind(
        id: "nearestVoicing", title: "Nearest voicing",
        instructions: "Play each chord low to high while it sounds, in the voicing nearest the one before.",
        symbol: "arrow.triangle.swap", rules: NearestVoicingRules.self)
}

/// Nearest voicing: the run's first chord, and one after a chord with no voicing played, accepts any voicing in the
/// position. After that, a chord accepts its voicings in the position with the least movement from the one actually
/// played, ties all accepted. The drawn path starts nearest the middle of the position and goes on to the nearest
/// voicing from the one played, or where none was, the one drawn.
public enum NearestVoicingRules: ProgressionRules {
    public static var kind: DrillKind { .nearestVoicing }

    public static func expected(for turn: ChordTurn) -> ExpectedVoicings? {
        let fretboard = turn.fretboard
        let accepted = turn.previousPlayed.map {
            fretboard.nearestVoicings(of: turn.triad, in: turn.position, to: $0)
        } ?? turn.voicings
        let from = turn.previousPlayed ?? turn.previousDrawn
        let drawn = from.flatMap { fretboard.nearestVoicings(of: turn.triad, in: turn.position, to: $0).first }
            ?? fretboard.middleVoicing(of: turn.triad, in: turn.position)
        return ExpectedVoicings(accepted: accepted, drawn: drawn)
    }
}
