import Testing
import TheoryCore

/// The frets of a position on each string, string 6 first.
private func fretsPerString(_ position: Position, strings: Int = 6) -> [[Int]] {
    (0..<strings).map { string in position.locations.filter { $0.string == string }.map(\.fret) }
}

@Suite("CAGED shapes in standard tuning")
struct CAGEDStandardTuningTests {
    let fretboard = Fretboard(tuning: .standard)
    let gMajorPentatonic = Scale(.majorPentatonic, tonic: .g)

    func position(_ shape: CAGEDShape, octave: Int = 0, of scale: Scale) -> Position? {
        fretboard.cagedPositions(of: scale).first { $0.cagedShape == shape && $0.octave == octave }
    }

    @Test func gMajorPentatonicEShape() throws {
        let e = try #require(position(.e, of: gMajorPentatonic))
        #expect(fretsPerString(e) == [[3, 5], [2, 5], [2, 5], [2, 4], [3, 5], [3, 5]])
        #expect(e.frets == 2...5)
        #expect(e.name == "E shape")
        #expect(e.system == .caged)
        #expect(e.number == 1)
    }

    @Test func gMajorPentatonicDShape() throws {
        let d = try #require(position(.d, of: gMajorPentatonic))
        // B-string shift: string 2 sits a fret higher than the strings below it.
        #expect(fretsPerString(d) == [[5, 7], [5, 7], [5, 7], [4, 7], [5, 8], [5, 7]])
        #expect(d.name == "D shape")
        #expect(d.number == 2)
    }

    @Test func gMajorPentatonicCShape() throws {
        let c = try #require(position(.c, of: gMajorPentatonic))
        #expect(fretsPerString(c) == [[7, 10], [7, 10], [7, 9], [7, 9], [8, 10], [7, 10]])
        #expect(c.frets == 7...10)
        #expect(c.name == "C shape")
    }

    @Test func gMajorPentatonicAShape() throws {
        let a = try #require(position(.a, of: gMajorPentatonic))
        #expect(fretsPerString(a) == [[10, 12], [10, 12], [9, 12], [9, 12], [10, 12], [10, 12]])
        #expect(a.name == "A shape")
    }

    @Test func gMajorPentatonicGShapeAtTheNut() throws {
        let g = try #require(position(.g, of: gMajorPentatonic))
        #expect(fretsPerString(g) == [[0, 3], [0, 2], [0, 2], [0, 2], [0, 3], [0, 3]])
        #expect(g.name == "G shape")
        #expect(g.number == 5)
    }

    @Test func octaveUpCopiesAreOfferedWhenTheyFit() throws {
        let all = fretboard.cagedPositions(of: gMajorPentatonic)
        // E 2–5 / 14–17, D 4–8 / 16–20, C 7–10 / 19–22, A 9–12 only (21–24 is past fret 22), G 0–3 / 12–15.
        #expect(all.map(\.frets) == [0...3, 2...5, 4...8, 7...10, 9...12, 12...15, 14...17, 16...20, 19...22])
        #expect(all.map(\.name) == ["G shape", "E shape", "D shape", "C shape", "A shape",
                                    "G shape", "E shape", "D shape", "C shape"])
        let eUp = try #require(position(.e, octave: 1, of: gMajorPentatonic))
        #expect(fretsPerString(eUp) == [[15, 17], [14, 17], [14, 17], [14, 16], [15, 17], [15, 17]])
        #expect(position(.a, octave: 1, of: gMajorPentatonic) == nil)
    }

    @Test func gMajorScaleEShapeAddsTheOtherNotesInsideTheWindow() throws {
        let e = try #require(position(.e, of: Scale(.major, tonic: .g)))
        #expect(fretsPerString(e) == [[2, 3, 5], [2, 3, 5], [2, 4, 5], [2, 4, 5], [3, 5], [2, 3, 5]])
        #expect(e.frets == 2...5)
    }

    @Test func cMajorEShapeIsAtFrets7To10() throws {
        let e = try #require(position(.e, of: Scale(.major, tonic: .c)))
        #expect(e.frets == 7...10)
    }

    @Test func minorKeysUseTheRelativeMajorsShapes() {
        let eMinorPentatonic = Scale(.minorPentatonic, tonic: .e)
        let major = fretboard.cagedPositions(of: gMajorPentatonic)
        let minor = fretboard.cagedPositions(of: eMinorPentatonic)
        #expect(minor.map(\.locations) == major.map(\.locations))
        #expect(minor.map(\.name) == major.map(\.name))
        #expect(minor.allSatisfy { $0.scale == eMinorPentatonic })
    }

    @Test func eMajorAShapeStretchesForItsFourth() throws {
        // Window 6–9. The A between G♯ (string 2, fret 9) and B (string 1, fret 7) is one fret over it.
        let a = try #require(position(.a, of: Scale(.major, tonic: .e)))
        #expect(fretsPerString(a) == [[7, 9], [6, 7, 9], [6, 7, 9], [6, 8, 9], [7, 9, 10], [7, 9]])
        #expect(a.frets == 6...10)
    }

    @Test func eMajorGShapeStretchesForItsSeventh() throws {
        // Window 9–12. The D♯ between C♯ (string 4, fret 11) and E (string 3, fret 9) is one fret under it.
        let g = try #require(position(.g, of: Scale(.major, tonic: .e)))
        #expect(fretsPerString(g) == [[9, 11, 12], [9, 11, 12], [9, 11], [8, 9, 11], [9, 10, 12], [9, 11, 12]])
        #expect(g.frets == 8...12)
    }

    @Test func atTheNutTheStretchGoesOnTheOtherString() throws {
        // F♯ would be a fret below the nut on string 3: it is on string 4, fret 4.
        let nut = try #require(position(.g, of: Scale(.naturalMinor, tonic: .e)))
        #expect(fretsPerString(nut) == [[0, 2, 3], [0, 2, 3], [0, 2, 4], [0, 2], [0, 1, 3], [0, 2, 3]])
        let up = try #require(position(.g, octave: 1, of: Scale(.naturalMinor, tonic: .e)))
        #expect(fretsPerString(up) == [[12, 14, 15], [12, 14, 15], [12, 14], [11, 12, 14], [12, 13, 15], [12, 14, 15]])
    }

    @Test func bluesAddsItsBlueNotesInsideTheWindowAndWhereOneIsSkipped() throws {
        // E blues uses G major's E-shape window, 2–5. Its B♭ (♭5) falls inside it only on
        // string 3 (G), fret 3. The low one, between A and B, is one fret over it on string 6.
        let e = try #require(position(.e, of: Scale(.blues, tonic: .e)))
        let blueNotes = e.locations.filter { fretboard.pitch(at: $0).pitchClass == PitchClass(10) }
        #expect(blueNotes == [FretboardLocation(string: 0, fret: 6), FretboardLocation(string: 3, fret: 3)])
        #expect(e.frets == 2...6)
    }
}

@Suite("CAGED shape starting degrees")
struct CAGEDStartingDegreeTests {
    @Test func startingDegreesByShape() {
        #expect(CAGEDShape.allCases.map(\.startingDegree) == [1, 2, 3, 5, 6])
    }

    @Test func eachShapeStartsOnItsDegreeOnString6() throws {
        let scale = Scale(.majorPentatonic, tonic: .c)
        let fretboard = Fretboard(tuning: .standard)
        for position in fretboard.cagedPositions(of: scale) {
            let shape = try #require(position.cagedShape)
            let lowest = try #require(position.locations.first { $0.string == 0 })
            let degree = try #require(scale.degree(of: fretboard.pitch(at: lowest).pitchClass))
            #expect(degree.number == shape.startingDegree, "\(position.name)")
        }
    }
}
