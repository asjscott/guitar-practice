import TheoryCore

extension DrillKind {
    public static let stayInPosition = DrillKind(
        id: "stayInPosition", title: "Stay in position",
        instructions: "Play each chord low to high while it sounds, in the voicing shown; each time through moves up.",
        symbol: "square.stack.3d.up", rules: StayInPositionRules.self)
}

/// Stay in position: time through *k* (from 0) expects each chord's voicing number *k* in the position, ordered up the
/// neck, wrapping per chord, so a few times through cover every voicing in the area. That voicing is the only one
/// accepted, and the one drawn.
public enum StayInPositionRules: ProgressionRules {
    public static var kind: DrillKind { .stayInPosition }

    public static func expected(for turn: ChordTurn) -> ExpectedVoicings {
        let voicing = turn.voicings[turn.timeThrough % turn.voicings.count]
        return ExpectedVoicings(accepted: [voicing], drawn: voicing)
    }
}
