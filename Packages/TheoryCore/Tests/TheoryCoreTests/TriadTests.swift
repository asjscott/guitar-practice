import Testing
import TheoryCore

@Suite("Triads")
struct TriadTests {
    @Test func majorAndMinorTriadNotes() {
        #expect(Triad(.major, root: .c).notes == [.c, .e, .g])
        #expect(Triad(.minor, root: .a).notes == [.a, .c, .e])
        #expect(Triad(.major, root: .bFlat).notes == [.bFlat, .d, .f])
        #expect(Triad(.minor, root: .dSharp).notes == [.dSharp, .fSharp, .aSharp])
        #expect(Triad(.major, root: .fSharp).notes == [.fSharp, .aSharp, .cSharp])
    }

    @Test func names() {
        #expect(Triad(.major, root: .c).name == "C major")
        #expect(Triad(.minor, root: .bFlat).name == "B♭ minor")
    }

    @Test func inversionsOrderTheTonesFromTheLowest() {
        let c = Triad(.major, root: .c)
        #expect(c.tones(in: .root) == [.c, .e, .g])
        #expect(c.tones(in: .first) == [.e, .g, .c])
        #expect(c.tones(in: .second) == [.g, .c, .e])
        #expect(Triad.Inversion.allCases == [.root, .first, .second])
        #expect(Triad.Inversion.allCases.map(\.name) == ["Root position", "1st inversion", "2nd inversion"])
    }

    @Test func aKeysTriadIsItsTonicTriad() {
        #expect(Key.major(.c).triad == Triad(.major, root: .c))
        #expect(Key.major(.eFlat).triad == Triad(.major, root: .eFlat))
        #expect(Key.minor(.a).triad == Triad(.minor, root: .a))
        #expect(Key.minor(.dSharp).triad == Triad(.minor, root: .dSharp))
    }
}

@Suite("A key's chords")
struct KeyChordTests {
    private func chords(_ key: Key) -> [String] { key.chords.map(\.name) }

    @Test func majorKeysLeaveOutTheDiminishedSeventhDegree() {
        #expect(chords(.major(.c)) == ["C major", "D minor", "E minor", "F major", "G major", "A minor"])
        #expect(chords(.major(.fSharp)) == ["F♯ major", "G♯ minor", "A♯ minor", "B major", "C♯ major", "D♯ minor"])
        #expect(chords(.major(.dFlat)) == ["D♭ major", "E♭ minor", "F minor", "G♭ major", "A♭ major", "B♭ minor"])
    }

    @Test func minorKeysLeaveOutTheDiminishedSecondDegree() {
        #expect(chords(.minor(.a)) == ["A minor", "C major", "D minor", "E minor", "F major", "G major"])
        #expect(chords(.minor(.dSharp)) == ["D♯ minor", "F♯ major", "G♯ minor", "A♯ minor", "B major", "C♯ major"])
        #expect(chords(.minor(.bFlat)) == ["B♭ minor", "D♭ major", "E♭ minor", "F minor", "G♭ major", "A♭ major"])
    }

    @Test(arguments: Key.appMajorKeys + Key.appMinorKeys)
    func everyChordIsMadeOfTheKeysNotesAsItSpellsThem(_ key: Key) {
        #expect(key.chords.count == 6)
        #expect(key.chords.first == key.triad)
        for chord in key.chords { #expect(Set(chord.notes).isSubset(of: key.notes)) }
    }
}

@Suite("Voicings in a fret range")
struct VoicingsInRangeTests {
    @Test func onlyVoicingsWhollyInTheRange() {
        let fretboard = Fretboard(tuning: .standard), c = Triad(.major, root: .c)
        func frets(_ range: ClosedRange<Int>) -> [[Int]] {
            fretboard.voicings(of: c, inversion: .second, on: .dGB, frets: range).map { $0.locations.map(\.fret) }
        }
        #expect(frets(0...12) == [[5, 5, 5]])
        #expect(frets(0...22) == [[5, 5, 5], [17, 17, 17]])
        #expect(fretboard.voicings(of: c, inversion: .root, on: .dGB, frets: 0...9).isEmpty)
    }
}

@Suite("String sets")
struct StringSetTests {
    @Test func fourStringSetsNamedByStandardOpenNotes() {
        #expect(StringSet.allCases.map(\.name) == ["E-A-D", "A-D-G", "D-G-B", "G-B-E"])
        #expect(StringSet.allCases.map(\.strings) == [0...2, 1...3, 2...4, 3...5])
        #expect(StringSet.dGB.lowestString == 2)
    }
}
