import Testing
import TheoryCore
import PracticeCore

@Suite("Skip")
struct SkipTests {
    @Test func skipRecordsASkippedAttemptAndShowsTheNextPromptWithNoReveal() {
        var drill = lowEDrill()
        drill.handle(.played(Pitch(43), onset: s(1), at: s(1.1)))
        drill.handle(.skip(at: s(2)))
        #expect(drill.phase == .waiting)
        #expect(drill.revealedLocations.isEmpty)
        #expect(drill.prompt?.target == FretboardLocation(string: 0, fret: 1))
        #expect(drill.promptStart == s(2))
        #expect(drill.attempts.count == 1)
        #expect(drill.attempts[0].outcome == .skipped)
        #expect(drill.attempts[0].responseTime == nil)
        #expect(!drill.attempts[0].timedOut)
        #expect(!drill.attempts[0].firstRight)
        #expect(drill.attempts[0].wrongNotes == [PitchClass(7)])
    }

    @Test func skipDuringTheRevealMovesOnWithoutAnotherAttempt() {
        var drill = lowEDrill()
        drill.handle(.tick(at: s(10.2)))
        drill.handle(.skip(at: s(10.5)))
        #expect(drill.phase == .waiting)
        #expect(drill.attempts.map(\.outcome) == [.timedOut])
        #expect(drill.promptStart == s(10.5))
    }

    @Test func skipDoesNothingWhenPausedOrIdle() {
        var drill = lowEDrill()
        drill.handle(.pause(at: s(1)))
        drill.handle(.skip(at: s(2)))
        #expect(drill.phase == .paused)
        drill.handle(.stop(at: s(3)))
        drill.handle(.skip(at: s(4)))
        #expect(drill.phase == .idle)
        #expect(drill.attempts.isEmpty)
    }

    @Test func aNotePlayedBeforeTheSkipDoesNotAnswerTheNextPrompt() {
        var drill = lowEDrill()
        drill.handle(.skip(at: s(2)))
        drill.handle(.played(Pitch(41), onset: s(1.9), at: s(2.05)))
        #expect(drill.phase == .waiting)
    }

    @Test func skipsCountInNeitherAccuracyNorMedianNorSlowest() {
        var drill = lowEDrill()
        drill.handle(.played(Pitch(40), onset: s(1), at: s(1.1)))
        drill.handle(.tick(at: s(1.5)))
        drill.handle(.skip(at: s(4)))
        drill.handle(.skip(at: s(5)))
        let stats = drill.stats
        #expect(stats.prompts == 1)
        #expect(stats.skips == 2)
        #expect(stats.firstTryAccuracy == 1)
        #expect(stats.medianResponseTime == s(1))
        #expect(stats.timeouts == 0)
        #expect(stats.slowest(3).count == 1)
        #expect(stats.misses.isEmpty)
    }

    @Test func skippedText() {
        var drill = lowEDrill()
        drill.handle(.skip(at: s(1)))
        #expect(drill.attempts[0].summaryLine(in: .standard) == "E on string 6 (E) — skipped")
        #expect(drill.attempts[0].shortTimeText == "skip")
        #expect(drill.attempts[0].rightAnswerText == nil)
    }
}

@Suite("Pause")
struct PauseTests {
    @Test func pauseHidesThePromptAndResumeGivesANewOne() throws {
        for seed in UInt64(1)...20 {
            var run = drill(seed: seed)
            run.handle(.start(at: s(0)))
            let old = try #require(run.prompt)
            run.handle(.played(Pitch(39), onset: s(1), at: s(1.1)))   // D♯: never right in naturals
            run.handle(.pause(at: s(3)))
            #expect(run.prompt == nil)
            #expect(run.display == nil)
            #expect(run.timeRemaining(at: s(3)) == nil)
            run.handle(.resume(at: s(100)))
            #expect(run.phase == .waiting)
            #expect(run.prompt != nil)
            #expect(run.prompt != old)
            #expect(run.promptStart == s(100))
            #expect(run.attempts.isEmpty)
        }
    }

    @Test func aCheckRunAsksForThePausedLocationAgainSoNoneIsMissed() {
        var check = lowEDrill(frets: 0...2)
        check.handle(.pause(at: s(1)))
        check.handle(.resume(at: s(2)))
        #expect(check.prompt?.target == FretboardLocation(string: 0, fret: 0))
    }
}

@Suite("Nothing to prompt")
struct NothingToPromptTests {
    @Test func naturalsOnAnEFlatTuningAtCapo12() {
        // E♭ standard, capo 12, frets 0–12: only E♭ A♭ D♭ G♭ B♭ E♭.
        let run = drill(TuningPreset.eFlatStandard.tuning, capo: 12)
        #expect(run.nothingToPromptReason == "No natural notes in these frets and strings. Choose All notes.")
        #expect(drill(TuningPreset.eFlatStandard.tuning, capo: 12) { $0.notes = .all }.nothingToPromptReason == nil)
        // A check ignores the Notes filter.
        #expect(drill(TuningPreset.eFlatStandard.tuning, capo: 12) { $0.order = .inOrder }.nothingToPromptReason == nil)
    }

    @Test func fretsAllBelowTheCapo() {
        #expect(drill(capo: 12) { $0.frets = 0...5 }.nothingToPromptReason == "The capo leaves no frets to play in this range.")
    }

    @Test func usuallyNoReason() {
        #expect(drill().nothingToPromptReason == nil)
    }
}
