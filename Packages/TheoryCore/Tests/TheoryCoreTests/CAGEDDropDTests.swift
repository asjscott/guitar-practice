import Testing
import TheoryCore

/// Drop D is standard tuning with the low string adjusted (ADR-0001): a CAGED shape keeps its
/// standard-tuning look on strings 5–1; only string 6 changes.
@Suite("CAGED shapes in Drop D")
struct CAGEDDropDTests {
    let standard = Fretboard(tuning: .standard)
    let dropD = Fretboard(tuning: TuningPreset.dropD.tuning)

    @Test func gMajorEShapeMatchesStandardOnStrings5To1() throws {
        let e = try #require(dropD.cagedPositions(of: Scale(.major, in: .major(.g)))
            .first { $0.cagedShape == .e && $0.octave == 0 })
        let frets = (0..<6).map { string in e.locations.filter { $0.string == string }.map(\.fret) }
        // String 6 (D): F♯ G A. Strings 5–1 as in standard tuning's G major E shape (frets 2–5),
        // with no F♯ at fret 7 on the B string.
        #expect(frets == [[4, 5, 7], [2, 3, 5], [2, 4, 5], [2, 4, 5], [3, 5], [2, 3, 5]])
        #expect(e.frets == 2...7)
    }

    static let scales: [Scale] = Key.appMajorKeys.flatMap { key in Scale.Kind.allCases.map { Scale($0, in: key) } }

    @Test(arguments: [0, 2])
    func everyShapeMatchesStandardOnStrings5To1(capo: Int) {
        let standard = Fretboard(tuning: .standard, capo: capo)
        let dropD = Fretboard(tuning: TuningPreset.dropD.tuning, capo: capo)
        for scale in Self.scales {
            let standardShapes = standard.cagedPositions(of: scale)
            for shape in dropD.cagedPositions(of: scale) {
                let upper = Set(shape.locations.filter { $0.string > 0 })
                // The same shape in standard tuning, at any placement (the low string can
                // move where it fits), shifted by whole octaves.
                let matches = standardShapes.filter { $0.number == shape.number }.contains { candidate in
                    let candidateUpper = candidate.locations.filter { $0.string > 0 }
                    return [-12, 0, 12].contains { shift in
                        Set(candidateUpper.map { FretboardLocation(string: $0.string, fret: $0.fret + shift) }) == upper
                    }
                }
                #expect(matches, "\(scale) \(shape.name) octave \(shape.octave) capo \(capo)")
            }
        }
    }
}
