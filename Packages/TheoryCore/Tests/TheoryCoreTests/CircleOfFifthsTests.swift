import Testing
import TheoryCore

@Suite("Circle of fifths")
struct CircleOfFifthsTests {
    private func names(_ keys: [Key]) -> String {
        keys.map(\.shortName).joined(separator: " ")
    }

    @Test func fromEMajor() {
        #expect(names(Key.major(.e).circleOfFifths) == "E B F♯ D♭ A♭ E♭ B♭ F C G D A")
    }

    @Test func fromCSharpMinor() {
        #expect(names(Key.minor(.cSharp).circleOfFifths) == "C♯m G♯m D♯m B♭m Fm Cm Gm Dm Am Em Bm F♯m")
    }

    @Test func fromCMajorIsTheGlossaryOrder() {
        #expect(names(Key.major(.c).circleOfFifths) == "C G D A E B F♯ D♭ A♭ E♭ B♭ F")
    }

    @Test func fromAMinor() {
        #expect(names(Key.minor(.a).circleOfFifths) == "Am Em Bm F♯m C♯m G♯m D♯m B♭m Fm Cm Gm Dm")
    }

    /// From every one of the 24 app keys: the same circle, rotated to start there.
    @Test(arguments: Key.appMajorKeys + Key.appMinorKeys)
    func everyAppKeyStartsTheSameCircleAtItself(key: Key) {
        let circle = key.circleOfFifths
        let reference = key.mode == .major
            ? "C G D A E B F♯ D♭ A♭ E♭ B♭ F" : "Am Em Bm F♯m C♯m G♯m D♯m B♭m Fm Cm Gm Dm"
        let order = reference.split(separator: " ").map(String.init)
        let start = order.firstIndex(of: key.shortName)!
        #expect(circle.map(\.shortName) == Array(order[start...] + order[..<start]))
        #expect(circle.first == key)
        #expect(Set(circle).count == 12)
        #expect(circle.allSatisfy { $0.mode == key.mode })
        #expect(Set(circle) == Set(Key.appKeys(key.mode)))
    }
}
