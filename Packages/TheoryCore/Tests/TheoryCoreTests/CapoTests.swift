import Testing
import TheoryCore

@Suite("Capo")
struct CapoTests {
    @Test func capoRunsFromNoneToFret12() {
        #expect(Fretboard.capoFrets == 0...12)
        #expect(Fretboard(tuning: .standard).capo == 0)
    }

    @Test func fretsBelowTheCapoAreUnplayable() {
        let capo3 = Fretboard(tuning: .standard, capo: 3)
        #expect(capo3.playableFrets == 3...22)
        #expect(!capo3.isPlayable(FretboardLocation(string: 0, fret: 0)))
        #expect(!capo3.isPlayable(FretboardLocation(string: 0, fret: 2)))
        #expect(capo3.isPlayable(FretboardLocation(string: 0, fret: 3)))
        #expect(capo3.allLocations.count == 6 * 20)
        #expect(capo3.allLocations.first == FretboardLocation(string: 0, fret: 3))
    }

    @Test func fretNumbersStillCountFromTheNut() {
        // With a capo at 2, fret 5 on string 6 is still A2, not B2.
        let capo2 = Fretboard(tuning: .standard, capo: 2)
        #expect(capo2.pitch(at: FretboardLocation(string: 0, fret: 5)) == Pitch(45))
    }

    @Test func capoRaisesEveryOpenString() {
        let capo2 = Fretboard(tuning: .standard, capo: 2)
        #expect(capo2.strings.map { capo2.soundingOpenPitch(ofString: $0).midi } == [42, 47, 52, 57, 61, 66])
        #expect(Fretboard(tuning: .standard).soundingOpenPitch(ofString: 0) == Pitch(40))
    }

    @Test func everyEWithCapoAt5InStandardTuning() {
        // The open-string Es and string 5's fret 7 are kept only where they sit at or above the capo.
        let expected = [
            (0, 12), (1, 7), (1, 19), (2, 14),
            (3, 9), (3, 21), (4, 5), (4, 17), (5, 12),
        ].map { FretboardLocation(string: $0.0, fret: $0.1) }
        #expect(Fretboard(tuning: .standard, capo: 5).locations(of: PitchClass(4)) == expected)
    }
}

@Suite("Locations in alternate tunings")
struct AlternateTuningLocationTests {
    @Test func everyDInDropD() {
        let expected = [
            (0, 0), (0, 12), (1, 5), (1, 17), (2, 0), (2, 12),
            (3, 7), (3, 19), (4, 3), (4, 15), (5, 10), (5, 22),
        ].map { FretboardLocation(string: $0.0, fret: $0.1) }
        #expect(Fretboard(tuning: TuningPreset.dropD.tuning).locations(of: PitchClass(2)) == expected)
    }

    @Test func everyGInDADGAD() {
        let expected = [
            (0, 5), (0, 17), (1, 10), (1, 22), (2, 5), (2, 17),
            (3, 0), (3, 12), (4, 10), (4, 22), (5, 5), (5, 17),
        ].map { FretboardLocation(string: $0.0, fret: $0.1) }
        #expect(Fretboard(tuning: TuningPreset.dadgad.tuning).locations(of: PitchClass(7)) == expected)
    }

    @Test func everyBInOpenG() {
        let expected = [
            (0, 9), (0, 21), (1, 4), (1, 16), (2, 9), (2, 21),
            (3, 4), (3, 16), (4, 0), (4, 12), (5, 9), (5, 21),
        ].map { FretboardLocation(string: $0.0, fret: $0.1) }
        #expect(Fretboard(tuning: TuningPreset.openG.tuning).locations(of: PitchClass(11)) == expected)
    }

    @Test func everyAInOpenGWithCapoAt2() {
        let expected = [
            (0, 7), (0, 19), (1, 2), (1, 14), (2, 7), (2, 19),
            (3, 2), (3, 14), (4, 10), (4, 22), (5, 7), (5, 19),
        ].map { FretboardLocation(string: $0.0, fret: $0.1) }
        #expect(Fretboard(tuning: TuningPreset.openG.tuning, capo: 2).locations(of: PitchClass(9)) == expected)
    }

    @Test(arguments: [TuningPreset.dropD, .dadgad, .openG, .openD, .eFlatStandard], [0, 3, 12])
    func locationsSoundThePitchClassAndLieBetweenCapoAnd22(preset: TuningPreset, capo: Int) {
        let fretboard = Fretboard(tuning: preset.tuning, capo: capo)
        for pitchClass in PitchClass.allCases {
            let locations = fretboard.locations(of: pitchClass)
            #expect(!locations.isEmpty)
            for location in locations {
                #expect(fretboard.pitch(at: location).pitchClass == pitchClass)
                #expect((capo...22).contains(location.fret))
            }
        }
    }
}
