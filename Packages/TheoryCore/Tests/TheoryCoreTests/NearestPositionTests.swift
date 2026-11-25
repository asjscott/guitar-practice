import Testing
import TheoryCore

private func id(_ shape: CAGEDShape) -> Position.ID { Position.ID(system: .caged, number: shape.number) }

@Suite("Nearest position of another scale")
struct NearestPositionTests {
    let fretboard = Fretboard(tuning: .standard)

    private func position(_ id: Position.ID, of scale: Scale) throws -> Position {
        try #require(fretboard.positions(of: scale, system: id.system).first { $0.id == id })
    }

    /// The 3NPS pattern from A on string 6 (fret 5); the blues G shape is at frets 5–8 too.
    @Test func aThreeNotesPerStringPatternGivesTheCAGEDShapeWithTheNearestLowestFret() throws {
        let blues = Scale(.blues, tonic: .a)
        let patterns = fretboard.positions(of: Scale(.naturalMinor, tonic: .a), system: .threeNotesPerString)
        let pattern = try #require(patterns.first { $0.locations.first == FretboardLocation(string: 0, fret: 5) })
        let found = try #require(fretboard.position(of: blues, nearest: pattern))
        #expect(found.scale == blues)
        #expect(found.id == id(.g))
    }

    @Test func aTieGoesToTheLowerFret() {
        let scale = Scale(.majorPentatonic, tonic: .c)
        let shapes = fretboard.cagedPositions(of: scale).map(\.frets.lowerBound)
        // Patterns of any key whose lowest fret is one from each of two shapes.
        var ties = 0
        for key in Key.appMajorKeys {
            for pattern in fretboard.positions(of: key.scale, system: .threeNotesPerString) {
                let low = pattern.frets.lowerBound
                guard shapes.contains(low - 1), shapes.contains(low + 1), !shapes.contains(low) else { continue }
                ties += 1
                #expect(fretboard.position(of: scale, nearest: pattern)?.frets.lowerBound == low - 1)
            }
        }
        #expect(ties > 0)
    }

    @Test func aCAGEDShapeGivesTheSameShape() throws {
        let major = try position(id(.d), of: Scale(.major, tonic: .a))
        #expect(fretboard.position(of: Scale(.majorPentatonic, tonic: .a), nearest: major)?.id == id(.d))
        #expect(fretboard.position(of: Scale(.major, tonic: .a), nearest: major) == major)
    }

    @Test func aSevenNoteScaleKeepsThePattern() throws {
        let major = Scale(.major, tonic: .g)
        let pattern = try position(.init(system: .threeNotesPerString, number: 4), of: major)
        #expect(fretboard.position(of: major, nearest: pattern) == pattern)
    }

    /// Not an octave away, even where the smaller scale also fits there.
    @Test(arguments: [(TuningPreset.standard, 0), (.standard, 3), (.dropD, 0), (.dadgad, 2), (.openG, 0), (.eFlatStandard, 7)])
    func inAnyTuningTheSameShapeIsInTheSamePlace(preset: TuningPreset, capo: Int) throws {
        let fretboard = Fretboard(tuning: preset.tuning, capo: capo)
        for key in Key.appMajorKeys + Key.appMinorKeys {
            for theme in fretboard.cagedPositions(of: key.scale) {
                for kind in Scale.Kind.allCases where kind.mode == key.mode {
                    let found = try #require(fretboard.position(of: Scale(kind, in: key), nearest: theme))
                    #expect(found.number == theme.number)
                    #expect(abs(found.frets.lowerBound - theme.frets.lowerBound) < 6)
                }
            }
        }
    }
}
