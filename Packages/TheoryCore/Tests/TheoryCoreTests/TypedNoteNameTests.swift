import Testing
import TheoryCore

@Suite("Typed note names")
struct TypedNoteNameTests {
    @Test(arguments: [("A", NoteName.a), ("g", .g), ("F#", .fSharp), ("f♯", .fSharp), ("b", .b), ("B", .b), ("Bb", .bFlat),
                      ("bb", .bFlat), ("BB", .bFlat), ("eb", .eFlat), ("D♭", .dFlat), ("E#", NoteName(.e, 1)), ("cb", .cFlat)])
    func parsingATypedName(text: String, name: NoteName) {
        #expect(NoteName(typed: text) == name)
    }

    @Test(arguments: ["", "H", "#", "♭", "#C", "C##", "Cbb", "bbb", "C#b", "CD", "C ", "1", "é"])
    func textThatIsNoNoteName(text: String) {
        #expect(NoteName(typed: text) == nil)
    }
}
