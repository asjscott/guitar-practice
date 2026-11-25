import Testing
import TheoryCore

private func at(_ string: Int, _ frets: Int...) -> [FretboardLocation] {
    frets.map { FretboardLocation(string: string, fret: $0) }
}

@Suite("Pass order in standard tuning")
struct PassOrderStandardTests {
    let fretboard = Fretboard(tuning: .standard)

    func position(_ shape: CAGEDShape, of scale: Scale) throws -> Position {
        try #require(fretboard.cagedPositions(of: scale).first { $0.cagedShape == shape && $0.octave == 0 })
    }

    @Test func cMajorEShapeFromItsRoot() throws {
        let order = fretboard.passOrder(of: try position(.e, of: Scale(.major, tonic: .c)), from: .init(1))
        let up = at(0, 8, 10) + at(1, 7, 8, 10) + at(2, 7, 9, 10) + at(3, 7, 9, 10) + at(4, 8, 10) + at(5, 7, 8, 10)
        let down = at(5, 8, 7) + at(4, 10, 8) + at(3, 10, 9, 7) + at(2, 10, 9, 7) + at(1, 10, 8, 7) + at(0, 10, 8, 7)
        #expect(order == up + down + at(0, 8))
    }

    @Test func aMinorPentatonicStartsAndEndsAtTheBottom() throws {
        let order = fretboard.passOrder(of: try position(.g, of: Scale(.minorPentatonic, tonic: .a)), from: .init(1))
        let up = at(0, 5, 8) + at(1, 5, 7) + at(2, 5, 7) + at(3, 5, 7) + at(4, 5, 8) + at(5, 5, 8)
        #expect(order == up + up.dropLast().reversed())
    }

    @Test func fromAnotherDegree() throws {
        let order = try #require(fretboard.passOrder(of: position(.g, of: Scale(.minorPentatonic, tonic: .a)), from: .init(3, -1)))
        #expect(order.count == 23)
        #expect(Array(order.prefix(2)) == at(0, 8) + at(1, 5))
        #expect(Array(order.suffix(3)) == at(0, 8, 5, 8))
    }

    @Test func aDegreeThePositionLacksHasNone() throws {
        #expect(fretboard.passOrder(of: try position(.e, of: Scale(.major, tonic: .c)), from: .init(3, -1)) == nil)
    }
}

@Suite("Pass order in any tuning")
struct PassOrderInvariantTests {
    static let setups: [(TuningPreset, Int)] = [
        (.standard, 0), (.standard, 3), (.dropD, 0), (.dropD, 5), (.dadgad, 0), (.dadgad, 2), (.openG, 0), (.openG, 7),
    ]

    @Test(arguments: setups)
    func risesThenFallsThenRisesBackToItsStart(preset: TuningPreset, capo: Int) throws {
        let fretboard = Fretboard(tuning: preset.tuning, capo: capo)
        var hasRepeats = false
        for scale in Key.appMajorKeys.flatMap({ key in Scale.Kind.allCases.map { Scale($0, in: key) } }) {
            let positions = fretboard.cagedPositions(of: scale) + fretboard.threeNPSPositions(of: scale)
            for position in positions {
                let pitches = Set(position.locations.map { fretboard.pitch(at: $0) })
                hasRepeats = hasRepeats || pitches.count < position.locations.count
                for degree in scale.kind.degrees {
                    let own = position.locations.map { fretboard.pitch(at: $0) }.filter { scale.degree(of: $0.pitchClass) == degree }
                    let order = fretboard.passOrder(of: position, from: degree)
                    guard let lowest = own.min() else {
                        #expect(order == nil)
                        continue
                    }
                    let locations = try #require(order)
                    let played = locations.map { fretboard.pitch(at: $0) }
                    #expect(played.first == lowest && played.last == lowest)
                    #expect(locations.first == locations.last)
                    #expect(Set(played) == pitches)
                    #expect(played.count == 2 * pitches.count - 1)
                    let top = try #require(played.firstIndex(of: pitches.max()!))
                    let bottom = try #require(played.lastIndex(of: pitches.min()!))
                    #expect(isRising(played[...top]))
                    #expect(isRising(played[top...bottom].reversed()))
                    #expect(isRising(played[bottom...]))
                    #expect(locations.allSatisfy { location in
                        position.locations.contains(location) && !position.locations.contains {
                            $0.string < location.string && fretboard.pitch(at: $0) == fretboard.pitch(at: location)
                        }
                    })
                }
            }
        }
        if preset == .dadgad || preset == .openG { #expect(hasRepeats) }
    }

    private func isRising(_ pitches: some Sequence<Pitch>) -> Bool {
        let pitches = Array(pitches)
        return zip(pitches, pitches.dropFirst()).allSatisfy { $0 < $1 }
    }
}
