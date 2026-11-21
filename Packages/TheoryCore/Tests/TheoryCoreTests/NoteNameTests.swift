import Testing
import TheoryCore

@Suite("Letters and note names")
struct NoteNameTests {
    @Test func letterSymbols() {
        #expect(Letter.allCases.map(\.symbol) == ["C", "D", "E", "F", "G", "A", "B"])
    }

    @Test func naturalPitchClasses() {
        #expect(Letter.allCases.map(\.naturalPitchClass.value) == [0, 2, 4, 5, 7, 9, 11])
    }

    @Test func advancingWrapsBothWays() {
        #expect(Letter.c.advanced(by: 2) == .e)
        #expect(Letter.a.advanced(by: 2) == .c) // A → B → C
        #expect(Letter.b.advanced(by: 1) == .c)
        #expect(Letter.c.advanced(by: -1) == .b)
        #expect(Letter.d.advanced(by: -2) == .b)
        #expect(Letter.g.advanced(by: 7) == .g)
        #expect(Letter.e.advanced(by: -15) == .d)
    }

    @Test func spellingAPitchClassOnALetter() {
        #expect(NoteName(.b, spelling: PitchClass(10)).description == "B♭")
        #expect(NoteName(.a, spelling: PitchClass(10)).description == "A♯")
        #expect(NoteName(.e, spelling: PitchClass(5)).description == "E♯")
        #expect(NoteName(.c, spelling: PitchClass(11)).description == "C♭")
        #expect(NoteName(.f, spelling: PitchClass(7)).description == "F𝄪")
        #expect(NoteName(.b, spelling: PitchClass(9)).description == "B𝄫")
        #expect(NoteName(.g, spelling: PitchClass(7)) == .g)
    }
}
