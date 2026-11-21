import Testing
import TheoryCore

/// The frets of a position on each string, string 6 first.
private func fretsPerString(_ position: Position, strings: Int = 6) -> [[Int]] {
    (0..<strings).map { string in position.locations.filter { $0.string == string }.map(\.fret) }
}

@Suite("3NPS patterns in standard tuning")
struct ThreeNPSStandardTuningTests {
    let fretboard = Fretboard(tuning: .standard)
    let gMajor = Scale(.major, tonic: .g)

    func pattern(_ number: Int, octave: Int = 0, of scale: Scale) -> Position? {
        fretboard.threeNPSPositions(of: scale).first { $0.number == number && $0.octave == octave }
    }

    @Test func gMajorPatterns() throws {
        // Pattern n starts on scale degree n on string 6; each string takes the next three notes.
        let expected: [[[Int]]] = [
            [[3, 5, 7], [3, 5, 7], [4, 5, 7], [4, 5, 7], [5, 7, 8], [5, 7, 8]],                   // 1: G
            [[5, 7, 8], [5, 7, 9], [5, 7, 9], [5, 7, 9], [7, 8, 10], [7, 8, 10]],                 // 2: A
            [[7, 8, 10], [7, 9, 10], [7, 9, 10], [7, 9, 11], [8, 10, 12], [8, 10, 12]],           // 3: B
            [[8, 10, 12], [9, 10, 12], [9, 10, 12], [9, 11, 12], [10, 12, 13], [10, 12, 14]],     // 4: C
            [[10, 12, 14], [10, 12, 14], [10, 12, 14], [11, 12, 14], [12, 13, 15], [12, 14, 15]], // 5: D
            [[0, 2, 3], [0, 2, 3], [0, 2, 4], [0, 2, 4], [1, 3, 5], [2, 3, 5]],                   // 6: E
            [[2, 3, 5], [2, 3, 5], [2, 4, 5], [2, 4, 5], [3, 5, 7], [3, 5, 7]],                   // 7: F♯
        ]
        for (index, frets) in expected.enumerated() {
            let number = index + 1
            let position = try #require(pattern(number, of: gMajor), "pattern \(number)")
            #expect(fretsPerString(position) == frets, "pattern \(number)")
            #expect(position.name == "Pattern \(number)")
            #expect(position.system == .threeNotesPerString)
            #expect(position.cagedShape == nil)
        }
    }

    @Test func octaveUpCopiesAreOfferedWhenTheyFit() throws {
        let all = fretboard.threeNPSPositions(of: gMajor)
        // Ordered up the neck by lowest fret, then pattern number.
        #expect(all.map(\.frets.lowerBound) == all.map(\.frets.lowerBound).sorted())
        let oneUp = try #require(pattern(1, octave: 1, of: gMajor))
        #expect(oneUp.frets == 15...20)
        #expect(pattern(3, octave: 1, of: gMajor) == nil) // 19–24 is past fret 22
        // Patterns 1, 2, 6 and 7 have octave-up copies; 3, 4 and 5 don't fit.
        #expect(all.count == 7 + 4)
    }

    @Test func cMajorPattern1StartsOnC() throws {
        let one = try #require(pattern(1, of: Scale(.major, tonic: .c)))
        #expect(fretsPerString(one) == [[8, 10, 12], [8, 10, 12], [9, 10, 12], [9, 10, 12], [10, 12, 13], [10, 12, 13]])
    }

    @Test func minorPatternsAreNumberedFromTheMinorTonic() throws {
        // E natural minor holds G major's notes; its pattern 1 starts on E (G major's pattern 6).
        let one = try #require(pattern(1, of: Scale(.naturalMinor, tonic: .e)))
        #expect(fretsPerString(one) == [[0, 2, 3], [0, 2, 3], [0, 2, 4], [0, 2, 4], [1, 3, 5], [2, 3, 5]])
    }

    @Test(arguments: [Scale.Kind.majorPentatonic, .minorPentatonic, .blues])
    func scalesWithoutSevenNotesHaveNoPatterns(kind: Scale.Kind) {
        #expect(fretboard.threeNPSPositions(of: Scale(kind, tonic: .a)).isEmpty)
    }
}

@Suite("Positions by position system")
struct PositionSystemTests {
    let fretboard = Fretboard(tuning: .standard)

    @Test func threeNPSGivesSevenPatternsForSevenNoteScales() {
        for kind in [Scale.Kind.major, .naturalMinor] {
            let positions = fretboard.positions(of: Scale(kind, tonic: .c), system: .threeNotesPerString)
            #expect(Set(positions.map(\.number)) == Set(1...7))
            #expect(positions.allSatisfy { $0.system == .threeNotesPerString })
        }
    }

    @Test(arguments: [Scale.Kind.majorPentatonic, .minorPentatonic, .blues])
    func pentatonicAndBluesFallBackToCAGED(kind: Scale.Kind) {
        let scale = Scale(kind, tonic: .c)
        #expect(fretboard.positions(of: scale, system: .threeNotesPerString) == fretboard.cagedPositions(of: scale))
    }

    @Test func cagedIsCAGEDForEveryScale() {
        for kind in Scale.Kind.allCases {
            let scale = Scale(kind, tonic: .c)
            #expect(fretboard.positions(of: scale, system: .caged) == fretboard.cagedPositions(of: scale))
        }
    }
}

@Suite("3NPS patterns in any tuning")
struct ThreeNPSInvariantTests {
    static let setups: [(TuningPreset, Int)] = [
        (.standard, 0), (.standard, 3), (.dropD, 0), (.dropD, 5), (.dadgad, 0), (.dadgad, 2),
        (.openG, 0), (.openG, 7), (.openD, 0), (.eFlatStandard, 0), (.standard, 12),
    ]

    static let scales: [Scale] = Key.appMajorKeys.flatMap { key in
        [Scale(.major, in: key), Scale(.naturalMinor, in: key)]
    }

    @Test(arguments: setups)
    func threeScaleNotesPerStringInsideTheFrets(preset: TuningPreset, capo: Int) {
        let fretboard = Fretboard(tuning: preset.tuning, capo: capo)
        for scale in Self.scales {
            for position in fretboard.threeNPSPositions(of: scale) {
                let pitchClasses = position.locations.map { fretboard.pitch(at: $0).pitchClass }
                #expect(pitchClasses.allSatisfy(scale.contains), "\(scale) \(position.name)")
                #expect(position.locations.allSatisfy(fretboard.isPlayable), "\(scale) \(position.name)")
                for string in fretboard.strings {
                    let onString = position.locations.filter { $0.string == string }
                    #expect(onString.count == 3, "\(scale) \(position.name) string \(string)")
                    #expect(Set(onString.map { fretboard.pitch(at: $0).pitchClass }).count == 3)
                }
            }
        }
    }

    @Test(arguments: setups)
    func eachPatternSitsAtTheLowestFitWithItsOctaveCopyWhenItFits(preset: TuningPreset, capo: Int) {
        let fretboard = Fretboard(tuning: preset.tuning, capo: capo)
        for scale in Self.scales {
            let positions = fretboard.threeNPSPositions(of: scale)
            for number in 1...7 {
                let copies = positions.filter { $0.number == number }.sorted { $0.octave < $1.octave }
                #expect(copies.count <= 2)
                guard let lowest = copies.first else { continue }
                #expect(lowest.octave == 0)
                // An octave lower would cross the capo (or the nut).
                #expect(lowest.frets.lowerBound - 12 < capo, "\(scale) \(lowest.name)")
                #expect((copies.count == 2) == (lowest.frets.upperBound + 12 <= 22), "\(scale) \(lowest.name)")
            }
            if capo == 0 {
                #expect(Set(positions.map(\.number)) == Set(1...7), "\(scale)")
            }
        }
    }
}
