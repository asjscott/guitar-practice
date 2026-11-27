import Testing
import PracticeCore

@Suite("Fade levels")
struct FadeLevelTests {
    @Test func levelZeroNeverFades() {
        #expect(FadeLevel.first.fadeTime(expected: s(10)) == nil)
    }

    @Test func levelsOneToFiveFadeByShrinkingSharesOfTheExpectedTime() {
        let times = (1...5).map { FadeLevel($0).fadeTime(expected: s(10)) }
        #expect(times == [s(9), s(6.8), s(5.1), s(3.8), s(2.8)])
    }

    @Test func theLastShowsOnlyTheRootsFromTheStart() {
        #expect(FadeLevel.last == FadeLevel(6))
        #expect(FadeLevel.last.fadeTime(expected: s(10)) == .zero)
    }

    @Test func levelsAreKeptWithinZeroToSix() {
        #expect(FadeLevel(-1) == .first)
        #expect(FadeLevel(7) == .last)
        #expect(FadeLevel.all.map(\.number) == Array(0...6))
    }

    @Test func oldStagesReadAsZeroTwoAndSix() {
        #expect(FadeStage.allCases.map { FadeLevel($0).number } == [0, 2, 6])
    }

    @Test func aNoteFadesLinearlyFromItsStart() {
        let fade = NoteFade(level: FadeLevel(1), expected: s(10), start: s(4))
        #expect(fade.opacity(at: s(0)) == 1)
        #expect(fade.opacity(at: s(4)) == 1)
        #expect(abs(fade.opacity(at: s(8.5)) - 0.5) < 1e-9)
        #expect(fade.opacity(at: s(13)) == 0)
        #expect(fade.opacity(at: s(20)) == 0)
    }

    @Test func atLevelZeroANoteStaysAndAtTheLastItIsNeverSeen() {
        #expect(NoteFade(level: .first, expected: s(10), start: s(4)).opacity(at: s(100)) == 1)
        #expect(NoteFade(level: .last, expected: s(10), start: s(4)).opacity(at: s(0)) == 0)
    }
}
