import Testing
import TheoryCore

@Suite("Tuning")
struct TuningTests {
    @Test func standardIsEADGBEFromString6() {
        #expect(Tuning.standard.openPitches == [40, 45, 50, 55, 59, 64].map(Pitch.init))
        #expect(Tuning.standard.stringCount == 6)
    }

    @Test func modelAllowsAnyStringCount() {
        let sevenString = Tuning([35, 40, 45, 50, 55, 59, 64].map(Pitch.init))
        #expect(sevenString.stringCount == 7)
        #expect(sevenString.openPitch(ofString: 0) == Pitch(35))
    }

    @Test func stringIndexZeroIsPhysicalString6() {
        // Internal index 0 = the low E (string 6); guitarist numbering counts down to string 1.
        #expect(Tuning.standard.openPitch(ofString: 0) == Pitch(40))
        #expect(Tuning.standard.openPitch(ofString: 5) == Pitch(64))
        #expect(Tuning.standard.stringNumber(ofString: 0) == 6)
        #expect(Tuning.standard.stringNumber(ofString: 5) == 1)
    }

    @Test func reEntrantTuningsKeepPhysicalOrder() {
        let reEntrant = Tuning([67, 60, 64, 69].map(Pitch.init)) // ukulele-style, high 4th string
        #expect(reEntrant.openPitches.map(\.midi) == [67, 60, 64, 69])
    }
}

@Suite("Fretboard")
struct FretboardTests {
    let standard = Fretboard(tuning: .standard)

    @Test func fretsRunFromNutTo22() {
        #expect(Fretboard.frets == 0...22)
        #expect(standard.playableFrets == 0...22)
        #expect(standard.strings == 0..<6)
    }

    @Test func allLocationsCoverEveryStringAndFret() {
        let all = standard.allLocations
        #expect(all.count == 6 * 23)
        #expect(all.first == FretboardLocation(string: 0, fret: 0))
        #expect(all[23] == FretboardLocation(string: 1, fret: 0))
        #expect(all.last == FretboardLocation(string: 5, fret: 22))
    }

    @Test func pitchAtALocationIsOpenStringPlusFret() {
        #expect(standard.pitch(at: FretboardLocation(string: 0, fret: 0)) == Pitch(40))
        #expect(standard.pitch(at: FretboardLocation(string: 0, fret: 8)) == Pitch(48))
        #expect(standard.pitch(at: FretboardLocation(string: 4, fret: 1)) == Pitch(60))
        #expect(standard.pitch(at: FretboardLocation(string: 5, fret: 22)) == Pitch(86))
    }

    @Test func everyCOnFrets0To22InStandardTuning() {
        let expected = [
            (0, 8), (0, 20),   // string 6
            (1, 3), (1, 15),   // string 5
            (2, 10), (2, 22),  // string 4
            (3, 5), (3, 17),   // string 3
            (4, 1), (4, 13),   // string 2
            (5, 8), (5, 20),   // string 1
        ].map { FretboardLocation(string: $0.0, fret: $0.1) }
        #expect(standard.locations(of: PitchClass(0)) == expected)
    }

    @Test func everyEIncludesOpenStringsAndTwelfthFret() {
        let expected = [
            (0, 0), (0, 12), (1, 7), (1, 19), (2, 2), (2, 14),
            (3, 9), (3, 21), (4, 5), (4, 17), (5, 0), (5, 12),
        ].map { FretboardLocation(string: $0.0, fret: $0.1) }
        #expect(standard.locations(of: PitchClass(4)) == expected)
    }

    @Test func everyMiddleCInStandardTuning() {
        let expected = [(0, 20), (1, 15), (2, 10), (3, 5), (4, 1)]
            .map { FretboardLocation(string: $0.0, fret: $0.1) }
        #expect(standard.locations(of: Pitch(60)) == expected)
    }

    @Test(arguments: PitchClass.allCases)
    func everyLocationOfAPitchClassSoundsThatPitchClass(pitchClass: PitchClass) {
        let locations = standard.locations(of: pitchClass)
        #expect(!locations.isEmpty)
        for location in locations {
            #expect(standard.pitch(at: location).pitchClass == pitchClass)
            #expect(standard.playableFrets.contains(location.fret))
        }
    }

    @Test func locationsFollowTheTuningsStringCount() {
        let sevenString = Fretboard(tuning: Tuning([35, 40, 45, 50, 55, 59, 64].map(Pitch.init)))
        #expect(sevenString.strings == 0..<7)
        #expect(sevenString.locations(of: PitchClass(11)).prefix(2)
            == [FretboardLocation(string: 0, fret: 0), FretboardLocation(string: 0, fret: 12)])
        #expect(sevenString.locations(of: PitchClass(0)).count == 14)
    }

    @Test func onlyLocationsOnTheNeckArePlayable() {
        #expect(standard.isPlayable(FretboardLocation(string: 5, fret: 22)))
        #expect(!standard.isPlayable(FretboardLocation(string: 6, fret: 0)))
        #expect(!standard.isPlayable(FretboardLocation(string: 0, fret: 23)))
        #expect(!standard.isPlayable(FretboardLocation(string: -1, fret: 3)))
    }
}
