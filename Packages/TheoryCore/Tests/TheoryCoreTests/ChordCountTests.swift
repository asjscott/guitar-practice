import Testing
import TheoryCore

@Suite("A key's chords on a string set")
struct ChordCountTests {
    @Test(arguments: [TuningPreset.standard, .dropD, .dadgad, .openG])
    func everyStringSetHasThemAllWithoutACapo(preset: TuningPreset) {
        let fretboard = Fretboard(tuning: preset.tuning)
        for key in Key.appMajorKeys + Key.appMinorKeys {
            for set in fretboard.stringSets { #expect(fretboard.chordCount(of: key, on: set) == 6) }
        }
    }

    /// In Drop D the only shapes on E-A-D are major in 2nd inversion, three frets down from the bass, and minor in 1st
    /// inversion, also three down. With the capo at 12 the bass is then on frets 15–22: the roots that leaves are B♭–F
    /// for major chords and D–A for minor ones.
    @Test func aCapoCanLeaveSomeOut() {
        let fretboard = Fretboard(tuning: TuningPreset.dropD.tuning, capo: 12)
        #expect(fretboard.chordCount(of: .major(.c), on: .eAD) == 5)     // no G major
        #expect(fretboard.chordCount(of: .minor(.a), on: .eAD) == 5)
        #expect(fretboard.chordCount(of: .major(.f), on: .eAD) == 6)
    }

    @Test func noneWhereTheStringsAreTooFarApart() {
        let wild = Fretboard(tuning: Tuning([24, 48, 72, 55, 59, 64].map(Pitch.init)), capo: 12)
        #expect(wild.chordCount(of: .major(.c), on: .eAD) == 0)
    }
}
