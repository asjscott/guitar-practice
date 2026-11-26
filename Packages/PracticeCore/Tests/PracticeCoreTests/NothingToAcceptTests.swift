import Testing
import PracticeCore
import TheoryCore

/// A chord the position has no voicing of (F♯ in G major's E shape), or a top note none of its voicings has: the rules
/// expect nothing rather than crash.
@Suite("Progression rules with nothing to accept")
struct NothingToAcceptTests {
    let fretboard = Fretboard(tuning: .standard)

    func eShape() throws -> Position {
        try #require(fretboard.cagedPositions(of: Key.major(.g).scale).first { $0.cagedShape == .e && $0.octave == 0 })
    }

    func turn(_ triad: Triad, in position: Position, topNote: Pitch? = nil) -> ChordTurn {
        ChordTurn(fretboard: fretboard, position: position, chords: [triad], index: 0, timeThrough: 3,
                  voicings: fretboard.voicings(of: triad, in: position), previousPlayed: nil, previousDrawn: nil,
                  topNote: topNote)
    }

    @Test func aChordWithNoVoicingInThePosition() throws {
        let fSharp = turn(Triad(.major, root: .fSharp), in: try eShape(), topNote: Pitch(66))
        #expect(fSharp.voicings.isEmpty)
        #expect(NearestVoicingRules.expected(for: fSharp) == nil)
        #expect(StayInPositionRules.expected(for: fSharp) == nil)
        #expect(TargetTopNoteRules.expected(for: fSharp) == nil)
    }

    @Test func aTopNoteNoVoicingHas() throws {
        let position = try eShape()
        let g = Triad(.major, root: .g)
        #expect(TargetTopNoteRules.expected(for: turn(g, in: position, topNote: Pitch(60))) == nil)
        #expect(TargetTopNoteRules.expected(for: turn(g, in: position)) == nil)
        #expect(TargetTopNoteRules.expected(for: turn(g, in: position, topNote: Pitch(67))) != nil)
    }
}
