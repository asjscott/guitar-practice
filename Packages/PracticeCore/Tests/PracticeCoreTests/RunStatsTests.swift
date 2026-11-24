import Testing
import TheoryCore
import PracticeCore

@Suite("Run stats")
struct RunStatsTests {
    /// String 6 in order: E, F, F♯, G, G♯ (frets 0–4).
    /// E right 1.0 s · F wrong (G) then right 2.5 s · F♯ times out after D · G right 0.5 s · G♯ right 3.0 s.
    func scriptedRun() -> NotePlayItDrill {
        var drill = lowEDrill(frets: 0...4)
        // E, prompt at 0.
        drill.handle(.played(Pitch(40), onset: s(1.0), at: s(1.1)))
        drill.handle(.tick(at: s(1.5)))
        // F, prompt at 1.5.
        drill.handle(.played(Pitch(43), onset: s(2.0), at: s(2.1)))
        drill.handle(.played(Pitch(41), onset: s(4.0), at: s(4.1)))
        drill.handle(.tick(at: s(4.5)))
        // F♯, prompt at 4.5: D, then time out at 14.5; next prompt at 16.3.
        drill.handle(.played(Pitch(38 + 12), onset: s(5.0), at: s(5.1)))
        drill.handle(.tick(at: s(14.5)))
        drill.handle(.tick(at: s(16.3)))
        // G, prompt at 16.3.
        drill.handle(.played(Pitch(43), onset: s(16.8), at: s(16.9)))
        drill.handle(.tick(at: s(17.3)))
        // G♯, prompt at 17.3.
        drill.handle(.played(Pitch(44), onset: s(20.3), at: s(20.4)))
        drill.handle(.tick(at: s(20.8)))
        return drill
    }

    @Test func theScriptRunsToTheEnd() {
        let drill = scriptedRun()
        #expect(drill.phase == .idle)
        #expect(drill.attempts.map(\.prompt.noteName) == ["E", "F", "F♯", "G", "G♯"])
    }

    @Test func statsForAScriptedRun() {
        let stats = scriptedRun().stats
        #expect(stats.prompts == 5)
        #expect(stats.firstTryRight == 3)
        #expect(stats.firstTryAccuracy == 0.6)
        // Times 1.0, 2.5, 0.5, 3.0 → median of 1.0 and 2.5.
        #expect(stats.medianResponseTime == s(1.75))
        #expect(stats.timeouts == 1)
    }

    @Test func slowestPromptsPutTimeoutsFirstThenTheLongestTimes() {
        let slowest = scriptedRun().stats.slowest(3)
        #expect(slowest.map(\.prompt.noteName) == ["F♯", "G♯", "F"])
        #expect(slowest[0].wrongNotes == [PitchClass(2)])
        #expect(slowest[1].responseTime == s(3.0))
        #expect(slowest[2].wrongNotes == [PitchClass(7)])
    }

    @Test func oddCountMedianIsTheMiddleTime() {
        let stats = RunStats(attempts: [0.4, 2.0, 0.9].map {
            Attempt(prompt: NotePrompt(pitchClass: PitchClass(0), string: 0), firstRight: true,
                    responseTime: s($0), wrongNotes: [], location: FretboardLocation(string: 0, fret: 8))
        })
        #expect(stats.medianResponseTime == s(0.9))
    }

    @Test func aSweepIsOnePrompt() {
        func attempt(_ sweep: Int, _ outcome: Attempt.Outcome, _ time: Double? = nil) -> Attempt {
            Attempt(prompt: NotePrompt(name: .c, string: 0, target: FretboardLocation(string: 0, fret: 8), sweep: sweep),
                    outcome: outcome, responseTime: time.map(s))
        }
        let whole = (0..<3).flatMap { sweep in (0..<6).map { attempt(sweep, .answered, Double($0 + 1)) } }
        #expect(RunStats(attempts: whole).prompts == 3)

        // A partial sweep counts once, as soon as it has an attempt. The rest is per attempt.
        let stats = RunStats(attempts: whole + [attempt(3, .timedOut), attempt(3, .skipped), attempt(4, .skipped)])
        #expect(stats.prompts == 5)
        #expect(stats.skips == 2)
        #expect(stats.firstTryAccuracy == 18.0 / 19)
        #expect(stats.medianResponseTime == s(3.5))
        #expect(RunStats(attempts: [attempt(0, .skipped)]).firstTryAccuracy == nil)
    }

    @Test func emptyRunHasNoAccuracyOrMedian() {
        let stats = RunStats(attempts: [])
        #expect(stats.prompts == 0)
        #expect(stats.firstTryAccuracy == nil)
        #expect(stats.medianResponseTime == nil)
        #expect(stats.timeouts == 0)
        #expect(stats.slowest(3).isEmpty)
    }
}
