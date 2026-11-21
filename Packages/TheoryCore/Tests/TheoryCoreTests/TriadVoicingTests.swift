import Testing
import TheoryCore

/// Frets of each voicing, lowest string of the set first, voicings ordered up the neck.
private func voicingFrets(_ triad: Triad, _ inversion: Triad.Inversion, _ set: StringSet,
                          on fretboard: Fretboard = Fretboard(tuning: .standard)) -> [[Int]] {
    fretboard.voicings(of: triad, inversion: inversion, on: set).map { $0.locations.map(\.fret) }
}

@Suite("Triad voicings in standard tuning")
struct StandardTriadVoicingTests {
    let cMajor = Triad(.major, root: .c)
    let aMinor = Triad(.minor, root: .a)

    @Test func cMajorOnEAD() {
        #expect(voicingFrets(cMajor, .root, .eAD) == [[8, 7, 5], [20, 19, 17]])
        #expect(voicingFrets(cMajor, .first, .eAD) == [[12, 10, 10]])
        #expect(voicingFrets(cMajor, .second, .eAD) == [[3, 3, 2], [15, 15, 14]])
    }

    @Test func cMajorOnADG() {
        #expect(voicingFrets(cMajor, .root, .aDG) == [[3, 2, 0], [15, 14, 12]])
        #expect(voicingFrets(cMajor, .first, .aDG) == [[7, 5, 5], [19, 17, 17]])
        #expect(voicingFrets(cMajor, .second, .aDG) == [[10, 10, 9], [22, 22, 21]])
    }

    @Test func cMajorOnDGB() {
        #expect(voicingFrets(cMajor, .root, .dGB) == [[10, 9, 8], [22, 21, 20]])
        #expect(voicingFrets(cMajor, .first, .dGB) == [[2, 0, 1], [14, 12, 13]])
        #expect(voicingFrets(cMajor, .second, .dGB) == [[5, 5, 5], [17, 17, 17]])
    }

    @Test func cMajorOnGBE() {
        #expect(voicingFrets(cMajor, .root, .gBE) == [[5, 5, 3], [17, 17, 15]])
        #expect(voicingFrets(cMajor, .first, .gBE) == [[9, 8, 8], [21, 20, 20]])
        #expect(voicingFrets(cMajor, .second, .gBE) == [[0, 1, 0], [12, 13, 12]])
    }

    @Test func aMinorOnEAD() {
        #expect(voicingFrets(aMinor, .root, .eAD) == [[5, 3, 2], [17, 15, 14]])
        #expect(voicingFrets(aMinor, .first, .eAD) == [[8, 7, 7], [20, 19, 19]])
        #expect(voicingFrets(aMinor, .second, .eAD) == [[12, 12, 10]])
    }

    @Test func aMinorOnADG() {
        #expect(voicingFrets(aMinor, .root, .aDG) == [[12, 10, 9]])
        #expect(voicingFrets(aMinor, .first, .aDG) == [[3, 2, 2], [15, 14, 14]])
        #expect(voicingFrets(aMinor, .second, .aDG) == [[7, 7, 5], [19, 19, 17]])
    }

    @Test func aMinorOnDGB() {
        #expect(voicingFrets(aMinor, .root, .dGB) == [[7, 5, 5], [19, 17, 17]])
        #expect(voicingFrets(aMinor, .first, .dGB) == [[10, 9, 10], [22, 21, 22]])
        #expect(voicingFrets(aMinor, .second, .dGB) == [[2, 2, 1], [14, 14, 13]])
    }

    @Test func aMinorOnGBE() {
        #expect(voicingFrets(aMinor, .root, .gBE) == [[2, 1, 0], [14, 13, 12]])
        #expect(voicingFrets(aMinor, .first, .gBE) == [[5, 5, 5], [17, 17, 17]])
        #expect(voicingFrets(aMinor, .second, .gBE) == [[9, 10, 8], [21, 22, 20]])
    }

    @Test func aVoicingKnowsItsChordStringsAndFrets() {
        let voicing = Fretboard(tuning: .standard).voicings(of: cMajor, inversion: .root, on: .eAD)[0]
        #expect(voicing.triad == cMajor)
        #expect(voicing.inversion == .root)
        #expect(voicing.stringSet == .eAD)
        #expect(voicing.locations == [FretboardLocation(string: 0, fret: 8),
                                      FretboardLocation(string: 1, fret: 7),
                                      FretboardLocation(string: 2, fret: 5)])
        #expect(voicing.frets == 5...8)
    }

    @Test func voicingsBelowTheCapoAreDropped() {
        // Capo 3: the open C-major shape on A-D-G (3 2 0) is gone; the 12th-fret copy stays.
        let capo3 = Fretboard(tuning: .standard, capo: 3)
        #expect(voicingFrets(cMajor, .root, .aDG, on: capo3) == [[15, 14, 12]])
    }

    @Test func theFretboardOffersEveryStringSetOfItsTuning() {
        #expect(Fretboard(tuning: .standard).stringSets == StringSet.allCases)
    }
}
