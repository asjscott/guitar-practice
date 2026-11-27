import Testing
import TheoryCore

@Suite("Position names")
struct PositionNameTests {
    @Test func cagedShapesAreNamedByLetterInStandardIntervalTunings() {
        let names = (1...5).map { Position.ID(system: .caged, number: $0).name(in: .standard) }
        #expect(names == ["E shape", "D shape", "C shape", "A shape", "G shape"])
        #expect(Position.ID(system: .caged, number: 4).name(in: TuningPreset.dropD.tuning) == "A shape")
    }

    @Test func elsewhereTheyAreNumbered() {
        #expect(Position.ID(system: .caged, number: 4).name(in: TuningPreset.dadgad.tuning) == "Position 4")
        #expect(Position.ID(system: .caged, number: 2).name(in: TuningPreset.openG.tuning) == "Position 2")
    }

    @Test func threeNPSPatternsAreNumberedInAnyTuning() {
        #expect(Position.ID(system: .threeNotesPerString, number: 3).name(in: .standard) == "Pattern 3")
        #expect(Position.ID(system: .threeNotesPerString, number: 7, octave: 1).name(in: TuningPreset.dadgad.tuning)
                == "Pattern 7")
    }

    @Test func aPositionsNameIsItsIDs() {
        for tuning in [Tuning.standard] + [TuningPreset.dropD, .dadgad, .openG].map(\.tuning) {
            let fretboard = Fretboard(tuning: tuning, capo: 2)
            for system in Position.System.allCases {
                for position in fretboard.positions(of: Scale(.major, tonic: .a), system: system) {
                    #expect(position.name == position.id.name(in: tuning))
                }
            }
        }
    }
}
