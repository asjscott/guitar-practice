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

@Suite("String sets")
struct StringSetTests {
    @Test func fourStringSetsNamedByStandardOpenNotes() {
        #expect(StringSet.allCases.map(\.name) == ["E-A-D", "A-D-G", "D-G-B", "G-B-E"])
        #expect(StringSet.allCases.map(\.strings) == [0...2, 1...3, 2...4, 3...5])
        #expect(StringSet.dGB.lowestString == 2)
    }
}
