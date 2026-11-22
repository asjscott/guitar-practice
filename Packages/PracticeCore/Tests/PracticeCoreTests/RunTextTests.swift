import Testing
import TheoryCore
import PracticeCore

@Suite("Run text")
struct RunTextTests {
    let f3 = NotePrompt(pitchClass: PitchClass(5), string: 3)

    func attempt(_ time: Double?, wrong: [Int] = []) -> Attempt {
        Attempt(prompt: f3, firstRight: time != nil && wrong.isEmpty, responseTime: time.map(s),
                wrongNotes: wrong.map(PitchClass.init), location: time == nil ? nil : FretboardLocation(string: 3, fret: 10))
    }

    @Test func summaryLineNamesThePromptTimeAndWrongNotesPlayedFirst() {
        #expect(attempt(2.314, wrong: [4, 7]).summaryLine(in: .standard) == "F on string 3 (G) — 2.31 s · played E, G first")
        #expect(attempt(0.5).summaryLine(in: .standard) == "F on string 3 (G) — 0.50 s")
    }

    @Test func statsTextRoundsAccuracyAndMedian() {
        let stats = RunStats(attempts: [attempt(1.0), attempt(1.234), attempt(2.0, wrong: [4]), attempt(nil, wrong: [6]),
                                        attempt(0.6), attempt(0.7)])
        // 4 of 6 first-try right (66.7%); median of 0.6 0.7 1.0 1.234 2.0 = 1.0.
        #expect(stats.firstTryText == "67%")
        #expect(stats.medianText == "1.00 s")
        #expect(RunStats(attempts: [attempt(1.0), attempt(nil), attempt(nil)]).firstTryText == "33%")
    }

    @Test func statsTextBeforeAnyPromptIsADash() {
        let stats = RunStats(attempts: [])
        #expect(stats.firstTryText == "–")
        #expect(stats.medianText == "–")
    }

    @Test func shortTimeForTheAttemptStrip() {
        #expect(attempt(2.34).shortTimeText == "2.3")
        #expect(attempt(nil).shortTimeText == "—")
    }

    @Test func rightAnswerFeedbackGivesTheFretAndTime() {
        #expect(attempt(0.816).rightAnswerText == "Fret 10 · 0.82 s")
        #expect(attempt(nil).rightAnswerText == nil)
    }

    @Test func missesAreTheAttemptsNotRightFirstTimeInOrder() {
        let wrongFirst = attempt(2.0, wrong: [4])
        let timedOut = attempt(nil)
        let stats = RunStats(attempts: [attempt(1.0), wrongFirst, attempt(0.5), timedOut])
        #expect(stats.misses == [wrongFirst, timedOut])
    }

    @Test func summaryLineForATimeout() {
        #expect(attempt(nil, wrong: [6]).summaryLine(in: .standard) == "F on string 3 (G) — timed out · played F♯ first")
    }
}
