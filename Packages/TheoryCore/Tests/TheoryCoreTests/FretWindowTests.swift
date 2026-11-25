import Testing
@testable import TheoryCore

/// The frets shown around a position: two either side, kept on the neck.
@Suite struct FretWindowTests {
    private func position(_ shape: CAGEDShape, _ tonic: NoteName, octave: Int = 0, on fretboard: Fretboard = Fretboard(tuning: .standard)) throws -> Position {
        try #require(fretboard.positions(of: Key.major(tonic).scale, system: .caged)
            .first { $0.cagedShape == shape && $0.octave == octave })
    }

    @Test func twoFretsEitherSide() throws {
        let e = try position(.e, .c)
        #expect(e.frets == 7...10)
        #expect(e.fretWindow == 5...12)
    }

    @Test func stopsAtTheNut() throws {
        let open = try position(.c, .c)
        #expect(open.frets == 0...3)
        #expect(open.fretWindow == 0...5)
    }

    @Test func stopsAtTheLastFret() throws {
        let high = try position(.e, .c, octave: 1)
        #expect(high.frets == 19...22)
        #expect(high.fretWindow == 17...22)
    }

    @Test(arguments: [(TuningPreset.dropD.tuning, 0), (TuningPreset.dadgad.tuning, 0), (TuningPreset.openG.tuning, 0), (Tuning.standard, 3)])
    func coversThePositionOnTheNeck(tuning: Tuning, capo: Int) {
        let fretboard = Fretboard(tuning: tuning, capo: capo)
        for key in Key.appMajorKeys {
            for position in fretboard.positions(of: key.scale, system: .caged) {
                let window = position.fretWindow
                #expect(position.locations.allSatisfy { window.contains($0.fret) })
                #expect(window.lowerBound >= 0 && window.upperBound <= 22)
            }
        }
    }
}
