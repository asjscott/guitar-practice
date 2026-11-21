import Testing
import TheoryCore

@Suite("Standard string intervals")
struct StandardIntervalTests {
    @Test(arguments: [
        (TuningPreset.standard, true), (.eFlatStandard, true), (.dropD, true),
        (.dadgad, false), (.openG, false), (.openD, false),
    ])
    func presets(preset: TuningPreset, expected: Bool) {
        #expect(preset.tuning.hasStandardIntervals == expected)
    }

    @Test func otherTunings() {
        #expect(Tuning([38, 43, 48, 53, 57, 62].map(Pitch.init)).hasStandardIntervals) // D standard
        #expect(!Tuning([40, 45, 50, 55, 59].map(Pitch.init)).hasStandardIntervals)    // 5 strings
        #expect(!Tuning([36, 45, 50, 55, 59, 64].map(Pitch.init)).hasStandardIntervals) // low C under A
    }
}

@Suite("CAGED shapes in any tuning")
struct CAGEDInvariantTests {
    static let setups: [(TuningPreset, Int)] = [
        (.standard, 0), (.standard, 3), (.dropD, 0), (.dropD, 5), (.dadgad, 0), (.dadgad, 2),
        (.openG, 0), (.openG, 7), (.openD, 0), (.eFlatStandard, 0), (.standard, 12),
    ]

    static let scales: [Scale] = Key.appMajorKeys.flatMap { key in Scale.Kind.allCases.map { Scale($0, in: key) } }

    @Test(arguments: setups)
    func everyPositionHoldsTheScaleTwoPentatonicNotesPerStringInsideTheFrets(preset: TuningPreset, capo: Int) {
        let fretboard = Fretboard(tuning: preset.tuning, capo: capo)
        for scale in Self.scales {
            let pentatonic = Set(Scale(.majorPentatonic, tonic: scale.key.relativeMajor.tonic).pitchClasses)
            for position in fretboard.cagedPositions(of: scale) {
                let pitchClasses = position.locations.map { fretboard.pitch(at: $0).pitchClass }
                #expect(pitchClasses.allSatisfy(scale.contains), "\(scale) \(position.name)")
                #expect(position.locations.allSatisfy(fretboard.isPlayable), "\(scale) \(position.name)")
                for string in fretboard.strings {
                    let onString = position.locations.filter { $0.string == string }
                    let pentatonicCount = onString.filter { pentatonic.contains(fretboard.pitch(at: $0).pitchClass) }.count
                    #expect(pentatonicCount == 2, "\(scale) \(position.name) string \(string)")
                    #expect(onString.allSatisfy { position.frets.contains($0.fret) })
                }
            }
        }
    }

    @Test(arguments: setups)
    func eachShapeSitsAtTheLowestFitWithItsOctaveCopyWhenItFits(preset: TuningPreset, capo: Int) {
        let fretboard = Fretboard(tuning: preset.tuning, capo: capo)
        for scale in Self.scales {
            let positions = fretboard.cagedPositions(of: scale)
            for number in 1...5 {
                let copies = positions.filter { $0.number == number }.sorted { $0.octave < $1.octave }
                #expect(copies.count <= 2)
                guard let lowest = copies.first else { continue }
                #expect(lowest.octave == 0)
                // An octave lower would cross the capo (or the nut).
                #expect(lowest.frets.lowerBound - 12 < capo, "\(scale) \(lowest.name)")
                let upFits = lowest.frets.upperBound + 12 <= 22
                #expect((copies.count == 2) == upFits, "\(scale) \(lowest.name)")
                if copies.count == 2 {
                    #expect(copies[1].octave == 1)
                    #expect(copies[1].locations.map(\.fret) == lowest.locations.map { $0.fret + 12 })
                }
            }
            if capo == 0 {
                #expect(Set(positions.map(\.number)) == [1, 2, 3, 4, 5], "\(scale)")
            }
        }
    }

    @Test(arguments: setups)
    func cagedNamesOnlyInStandardIntervalTunings(preset: TuningPreset, capo: Int) {
        let fretboard = Fretboard(tuning: preset.tuning, capo: capo)
        for position in fretboard.cagedPositions(of: Scale(.major, tonic: .c)) {
            let shape = CAGEDShape(number: position.number)!
            let expected = preset.tuning.hasStandardIntervals ? "\(shape.letter) shape" : "Position \(position.number)"
            #expect(position.name == expected)
            #expect(position.cagedShape == shape)
        }
    }

    @Test func positionsAreOrderedUpTheNeck() {
        let fretboard = Fretboard(tuning: TuningPreset.dadgad.tuning)
        let starts = fretboard.cagedPositions(of: Scale(.major, tonic: .d)).map(\.frets.lowerBound)
        #expect(starts == starts.sorted())
    }

    @Test func dropDShapesMatchStandardAboveTheLowString() {
        // Drop D only moves string 6; the pentatonic notes on the other five strings are unchanged.
        // (Seven-note scales can gain notes there: string 6 widens the window.)
        let scale = Scale(.majorPentatonic, tonic: .g)
        let standard = Fretboard(tuning: .standard).cagedPositions(of: scale)
        let dropD = Fretboard(tuning: TuningPreset.dropD.tuning).cagedPositions(of: scale)
        for position in standard where position.octave == 0 {
            let match = dropD.first { $0.number == position.number && $0.octave == 0 }
            #expect(match?.locations.filter { $0.string > 0 } == position.locations.filter { $0.string > 0 })
        }
    }
}
