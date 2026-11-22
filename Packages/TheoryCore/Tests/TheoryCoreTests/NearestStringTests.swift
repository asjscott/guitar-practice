import Testing
import TheoryCore

@Suite("Nearest string (tuner)")
struct NearestStringTests {
    @Test func eachOpenPitchFindsItsOwnStringInStandard() {
        // E2 A2 D3 G3 B3 E4 → strings 6…1 (index 0…5).
        for (index, midi) in [40, 45, 50, 55, 59, 64].enumerated() {
            #expect(Tuning.standard.nearestString(to: Pitch(midi)) == index)
        }
    }

    @Test func aNoteBetweenStringsFindsTheCloserOne() {
        // F2 (41) is 1 above E2, 4 below A2 → string 6. G♯2 (44) is 1 below A2 → string 5.
        #expect(Tuning.standard.nearestString(to: Pitch(41)) == 0)
        #expect(Tuning.standard.nearestString(to: Pitch(44)) == 1)
    }

    @Test func centsBreakAnEvenSplit() {
        // A3 (57) is 2 above G3 (55) and 2 below B3 (59).
        #expect(Tuning.standard.nearestString(to: Pitch(57), cents: 30) == 4)
        #expect(Tuning.standard.nearestString(to: Pitch(57), cents: -30) == 3)
    }

    @Test func anExactTieGoesToTheLowerStringIndex() {
        #expect(Tuning.standard.nearestString(to: Pitch(57)) == 3)
    }

    @Test func pitchesBeyondTheStringsFindTheOuterStrings() {
        #expect(Tuning.standard.nearestString(to: Pitch(30)) == 0)
        #expect(Tuning.standard.nearestString(to: Pitch(90)) == 5)
    }

    @Test func followsDropDAndDADGAD() {
        // Drop D: D2 (38) is string 6, E2 (40) is now nearer D2 than A2.
        #expect(TuningPreset.dropD.tuning.nearestString(to: Pitch(38)) == 0)
        #expect(TuningPreset.dropD.tuning.nearestString(to: Pitch(40)) == 0)
        // DADGAD (D2 A2 D3 G3 A3 D4): A3 (57) is string 2, D4 (62) is string 1.
        let dadgad = TuningPreset.dadgad.tuning
        #expect(dadgad.nearestString(to: Pitch(57)) == 4)
        #expect(dadgad.nearestString(to: Pitch(62)) == 5)
        #expect(dadgad.nearestString(to: Pitch(50)) == 2)
    }

    @Test func reEntrantTuningsMatchByPitchNotOrder() {
        // Re-entrant: string 1 tuned down to E3 (52), below strings 3 and 2.
        let reEntrant = Tuning([40, 45, 50, 55, 59, 52].map(Pitch.init))
        #expect(reEntrant.nearestString(to: Pitch(52)) == 5)
        #expect(reEntrant.nearestString(to: Pitch(50)) == 2)
    }
}

@Suite("Tuner note names")
struct TuningNoteNameTests {
    @Test func sharpsInSharpTunings() {
        #expect(Tuning.standard.noteName(of: PitchClass(1)).description == "C♯")
        #expect(TuningPreset.dadgad.tuning.noteName(of: PitchClass(6)).description == "F♯")
    }

    @Test func flatsInEFlatStandard() {
        let eFlat = TuningPreset.eFlatStandard.tuning
        #expect(eFlat.noteName(of: PitchClass(3)).description == "E♭")
        #expect(eFlat.noteName(of: PitchClass(10)).description == "B♭")
        #expect(eFlat.noteName(of: PitchClass(4)).description == "E")
    }
}
