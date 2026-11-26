import TheoryCore

extension DrillKind {
    public static let targetTopNote = DrillKind(
        id: "targetTopNote", title: "Target top note",
        instructions: "Play each chord low to high while it sounds, in a voicing with the line’s note on top.",
        symbol: "point.topleft.down.to.point.bottomright.curvepath", rules: TargetTopNoteRules.self)
}

/// Target top note: a melody on the top notes (`Fretboard.topNoteLine`), drawn over the timeline at every fade stage.
/// A chord accepts any of its voicings in the position with the line's note on top. The one drawn is the nearest of
/// those to the voicing played before, or where none was, to the one drawn; the first chord's is the lowest up the
/// neck.
public enum TargetTopNoteRules: ProgressionRules {
    public static var kind: DrillKind { .targetTopNote }

    public static func topNotes(of progression: Progression, in key: Key, position: Position,
                                on fretboard: Fretboard) -> [Pitch]? {
        fretboard.topNoteLine(of: progression, in: key, position: position)
    }

    public static func expected(for turn: ChordTurn) -> ExpectedVoicings {
        let fretboard = turn.fretboard
        let accepted = turn.voicings.filter { fretboard.pitch(at: $0.locations[2]) == turn.topNote }
        let from = turn.previousPlayed ?? turn.previousDrawn
        let drawn = from.map { from in
            accepted.min { fretboard.movement(from: from, to: $0) < fretboard.movement(from: from, to: $1) }!
        } ?? accepted[0]
        return ExpectedVoicings(accepted: accepted, drawn: drawn)
    }
}
