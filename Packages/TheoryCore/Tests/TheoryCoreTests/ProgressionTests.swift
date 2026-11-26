import Testing
import TheoryCore

private func names(_ progression: Progression, in key: Key) -> [String] {
    progression.chords(in: key).map { "\($0.root)\($0.quality == .minor ? "m" : "")" }
}

private func progression(_ id: String) throws -> Progression {
    try #require(Progression.named(id))
}

@Suite("Progressions")
struct ProgressionTests {
    @Test func theLibraryHasEightInOrder() {
        #expect(Progression.library.map(\.id) == [
            "I–IV–V", "I–V–vi–IV", "ii–V–I", "I–vi–IV–V", "vi–IV–I–V", "12-bar blues", "i–iv–v", "i–VI–III–VII",
        ])
    }

    @Test func eachModeHasItsOwn() {
        #expect(Progression.library(.major).count == 6)
        #expect(Progression.library(.minor).map(\.id) == ["i–iv–v", "i–VI–III–VII"])
        #expect(Progression.library.allSatisfy { p in p.steps.allSatisfy { $0.bars >= 1 } })
    }

    @Test func onlyThe12BarBluesShuffles() {
        #expect(Progression.library.filter { $0.feel == .shuffle }.map(\.id) == ["12-bar blues"])
        #expect(Progression.library.filter { $0.feel == .straight }.count == 7)
    }

    @Test func numeralsAreWrittenWithTheirCase() throws {
        #expect(try progression("I–V–vi–IV").steps.map(\.numeral.text) == ["I", "V", "vi", "IV"])
        #expect(try progression("i–VI–III–VII").steps.map(\.numeral.text) == ["i", "VI", "III", "VII"])
    }

    @Test func iVviIVInGIsGDEmC() throws {
        #expect(names(try progression("I–V–vi–IV"), in: .major(.g)) == ["G", "D", "Em", "C"])
    }

    @Test func minorProgressionsRenderFromTheScaleNotTheChordList() throws {
        // A minor's chord list leaves out the diminished ii°, so its indices aren't degrees.
        #expect(names(try progression("i–VI–III–VII"), in: .minor(.a)) == ["Am", "F", "C", "G"])
        #expect(names(try progression("i–iv–v"), in: .minor(.a)) == ["Am", "Dm", "Em"])
    }

    @Test func chordsAreSpelledInTheKey() throws {
        #expect(names(try progression("i–VI–III–VII"), in: .minor(.dSharp)) == ["D♯m", "B", "F♯", "C♯"])
        #expect(names(try progression("I–IV–V"), in: .major(.f)) == ["F", "B♭", "C"])
        #expect(names(try progression("vi–IV–I–V"), in: .major(.dFlat)) == ["B♭m", "G♭", "D♭", "A♭"])
    }

    @Test func iiVIHasTwoBarsOnTheI() throws {
        let p = try progression("ii–V–I")
        #expect(p.steps.map(\.bars) == [1, 1, 2])
        #expect(names(p, in: .major(.c)) == ["Dm", "G", "C"])
    }

    @Test func theTwelveBarBluesPlaysMajorTriads() throws {
        let blues = try progression("12-bar blues")
        #expect(blues.steps.count == 12)
        #expect(blues.steps.allSatisfy { $0.bars == 1 })
        #expect(names(blues, in: .major(.a)) == ["A", "A", "A", "A", "D", "D", "A", "A", "E", "D", "A", "E"])
    }

    @Test func everyChordIsInItsKeyInAll24Keys() {
        for key in Key.appMajorKeys + Key.appMinorKeys {
            for p in Progression.library(key.mode) {
                let chords = p.chords(in: key)
                #expect(chords.count == p.steps.count)
                for chord in chords { #expect(chord.notes.allSatisfy(key.notes.contains), "\(p.id) in \(key)") }
                let first = ["vi–IV–I–V": 5, "ii–V–I": 1][p.id] ?? 0
                #expect(chords.first?.root == key.notes[first])
            }
        }
    }

    @Test func unknownIdsAreNil() {
        #expect(Progression.named("I–II") == nil)
    }
}
