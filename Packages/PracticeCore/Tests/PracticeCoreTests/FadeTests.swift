import Testing
import TheoryCore
import PracticeCore

private let eShape = FadeLevels.Subject(tuning: .standard, scaleKind: .major, position: .init(system: .caged, number: 1))

/// A pass of three notes, one attempt each.
private func pass(_ subject: FadeLevels.Subject = eShape, at level: Int = 0, clean: Bool = true,
                  hinted: Bool = false, places: [Int] = [0, 1, 2], last: Attempt.Outcome = .answered) -> [FadeLevels.Note] {
    places.map { place in
        let outcome: Attempt.Outcome = place == places.last ? last : .answered
        return FadeLevels.Note(subject: subject, level: FadeLevel(level), hinted: hinted && place > 0, size: 3, place: place,
                               outcome: outcome, firstRight: outcome == .answered && (clean || place != 1))
    }
}

/// A pass logged before fade levels, at a stage.
private func oldPass(at stage: FadeStage, clean: Bool = true) -> [FadeLevels.Note] {
    (0..<3).map { place in
        FadeLevels.Note(subject: eShape, stage: stage, hinted: false, size: 3, place: place, outcome: .answered,
                        firstRight: clean || place != 1)
    }
}

/// Clean passes from level 0 up to `level`.
private func climb(to level: Int) -> [[FadeLevels.Note]] { (0..<level).map { pass(at: $0) } }

/// As the log has them, each pass a group.
private func fold(_ passes: [[FadeLevels.Note]]) -> FadeLevels {
    FadeLevels(log: passes.enumerated().flatMap { number, notes in notes.map { (group: number, note: $0) } })
}

private func level(after passes: [FadeLevels.Note]...) -> Int { fold(passes).level(of: eShape).number }
private func level(after passes: [[FadeLevels.Note]]) -> Int { fold(passes).level(of: eShape).number }

@Suite("Fade levels from the log")
struct FadeLevelsTests {
    @Test func aNewSubjectStartsAtLevelZero() {
        #expect(level() == 0)
        #expect(FadeLevels().level(of: eShape) == .first)
    }

    @Test func oneUpForEachCleanPassUpToTheLast() {
        #expect(level(after: pass()) == 1)
        #expect(level(after: pass(), pass(at: 1)) == 2)
        #expect(level(after: climb(to: 6)) == 6)
        #expect(level(after: climb(to: 6) + [pass(at: 6)]) == 6)
    }

    @Test func oneDownForEachOtherPassDownToZero() {
        #expect(level(after: pass(clean: false)) == 0)
        #expect(level(after: pass(), pass(at: 1, clean: false)) == 0)
        #expect(level(after: climb(to: 3) + [pass(at: 3, clean: false)]) == 2)
        #expect(level(after: climb(to: 6) + [pass(at: 6, clean: false)]) == 5)
    }

    @Test func aHintOrATimeoutIsntClean() {
        #expect(level(after: pass(), pass(at: 1, hinted: true)) == 0)
        #expect(level(after: pass(), pass(at: 1, last: .timedOut)) == 0)
    }

    @Test func passesPlayedAtAnotherLevelDontCount() {
        #expect(level(after: pass(at: 6)) == 0)
        #expect(level(after: pass(), pass(at: 0, clean: false)) == 1)
        #expect(level(after: pass(), pass(at: 6, clean: false), pass(at: 1)) == 2)
    }

    @Test func aPassCutShortCountsNeitherWay() {
        #expect(level(after: pass(), pass(at: 1, clean: false, places: [0, 1])) == 1)
        #expect(level(after: pass(places: [0, 1])) == 0)
        // A skip cuts it short, on the last note too.
        #expect(level(after: pass(), pass(at: 1, last: .skipped)) == 1)
        // A pass started again is another group: two halves aren't a whole.
        #expect(level(after: pass(places: [0, 1]), pass(places: [2])) == 0)
        #expect(level(after: pass(places: [0, 1, 1])) == 0)
    }

    @Test func theNotesOfAGroupNeedntBeInOrder() {
        #expect(level(after: pass(places: [2, 0, 1])) == 1)
    }

    @Test func keptPerScaleKindPositionAndTuning() {
        var other = eShape
        other.position = .init(system: .caged, number: 2)
        #expect(level(after: pass(other)) == 0)
        other = eShape
        other.position = .init(system: .threeNotesPerString, number: 1)
        #expect(level(after: pass(other)) == 0)
        other = eShape
        other.scaleKind = .majorPentatonic
        #expect(level(after: pass(other)) == 0)
        other = eShape
        other.tuning = TuningPreset.dropD.tuning
        #expect(level(after: pass(other)) == 0)
    }

    @Test func theOctaveIsIgnored() {
        var octaveUp = eShape
        octaveUp.position = .init(system: .caged, number: 1, octave: 1)
        #expect(level(after: pass(octaveUp)) == 1)
        #expect(fold([pass()]).level(of: octaveUp) == FadeLevel(1))
    }

    /// Shown, Faded and Hidden read as 0, 2 and 6, and moved between them as the stages did, so nothing is lost.
    @Test func oldStagesCarryOver() {
        #expect(level(after: oldPass(at: .shown)) == 2)
        #expect(level(after: oldPass(at: .shown), oldPass(at: .faded)) == 6)
        #expect(level(after: oldPass(at: .shown), oldPass(at: .faded), oldPass(at: .hidden, clean: false)) == 2)
        #expect(level(after: oldPass(at: .faded)) == 0)
        #expect(level(after: oldPass(at: .shown), pass(at: 2)) == 3)
        #expect(level(after: oldPass(at: .shown), oldPass(at: .faded), pass(at: 6, clean: false)) == 5)
    }
}
