import Testing
import TheoryCore

private func at(_ string: Int, _ frets: Int...) -> [FretboardLocation] {
    frets.map { FretboardLocation(string: string, fret: $0) }
}

@Suite("One-way passes")
struct OneWayPassTests {
    @Test func upGoesFromTheBottomToTheTopAndDownBack() throws {
        let fretboard = Fretboard(tuning: .standard)
        let position = try #require(fretboard.cagedPositions(of: Scale(.minorPentatonic, tonic: .a))
            .first { $0.cagedShape == .g && $0.octave == 0 })
        let up = at(0, 5, 8) + at(1, 5, 7) + at(2, 5, 7) + at(3, 5, 7) + at(4, 5, 8) + at(5, 5, 8)
        #expect(fretboard.passOrder(of: position, going: .up) == up)
        #expect(fretboard.passOrder(of: position, going: .down) == up.reversed())
    }

    /// Each pitch once, on the lower string, as in a pass up and down.
    @Test(arguments: [TuningPreset.standard, .dropD, .dadgad, .openG])
    func eachPitchOnceInPitchOrder(preset: TuningPreset) {
        let fretboard = Fretboard(tuning: preset.tuning)
        for position in fretboard.positions(of: Scale(.major, tonic: .g), system: .caged) {
            let up = fretboard.passOrder(of: position, going: .up)
            let pitches = up.map(fretboard.pitch)
            #expect(pitches == pitches.sorted())
            #expect(Set(pitches).count == pitches.count)
            #expect(Set(pitches) == Set(position.locations.map(fretboard.pitch)))
            #expect(Set(up) == Set(fretboard.passOrder(of: position, from: .init(1)) ?? []))
        }
    }

    @Test func theDirectionsTakeTurnsAndAreSavedAsUpAndDown() {
        #expect(PassDirection.up.reversed == .down)
        #expect(PassDirection.down.reversed == .up)
        #expect(PassDirection.up.rawValue == "up")
        #expect(PassDirection.down.rawValue == "down")
    }
}
