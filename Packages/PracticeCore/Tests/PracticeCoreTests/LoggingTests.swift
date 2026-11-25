import Testing
import TheoryCore
import PracticeCore

@Suite("What the attempt log gets")
struct LoggingTests {
    @Test func playedWrongAnswersKeepTheirOctave() {
        var drill = lowEDrill()
        drill.handle(.played(Pitch(64), onset: s(0.5), at: s(0.6)))   // E4: the right note, the wrong octave
        drill.handle(.played(Pitch(43), onset: s(1.0), at: s(1.1)))   // G2
        drill.handle(.played(Pitch(40), onset: s(1.7), at: s(1.8)))
        #expect(drill.attempts[0].rawWrongAnswers == [.played(Pitch(64)), .played(Pitch(43))])
        #expect(drill.attempts[0].wrongNotes == [PitchClass(4), PitchClass(7)])
    }

    @Test func timedOutAndSkippedAttemptsKeepThemToo() {
        var drill = lowEDrill()
        drill.handle(.played(Pitch(43), onset: s(2), at: s(2.1)))
        drill.handle(.tick(at: s(10.2)))
        drill.handle(.tick(at: s(13)))
        drill.handle(.played(Pitch(55), onset: s(14), at: s(14.1)))
        drill.handle(.skip(at: s(15)))
        #expect(drill.attempts.map(\.outcome) == [.timedOut, .skipped])
        #expect(drill.attempts.map(\.rawWrongAnswers) == [[.played(Pitch(43))], [.played(Pitch(55))]])
    }

    @Test func typedWrongAnswersKeepTheirSpelling() {
        #expect(WrongAnswer.name(.bFlat).raw == .named(.bFlat))
        #expect(Attempt(prompt: NotePrompt(pitchClass: PitchClass(0), string: 0), outcome: .skipped,
                        wrongAnswers: [.name(.bFlat), .pitch(Pitch(45))]).rawWrongAnswers
                == [.named(.bFlat), .played(Pitch(45))])
    }

    @Test func pausedAndStoppedPromptsLeaveNothingToLog() {
        var run = drill()
        run.handle(.start(at: s(0)))
        run.handle(.played(Pitch(39), onset: s(1), at: s(1.1)))
        run.handle(.pause(at: s(3)))
        run.handle(.resume(at: s(5)))
        run.handle(.stop(at: s(6)))
        #expect(run.attemptsToLog.isEmpty)
    }

    @Test func aRunsAttemptsAreForTheLog() {
        var run = drill()
        run.handle(.start(at: s(0)))
        run.handle(.skip(at: s(1)))
        run.handle(.tick(at: s(12)))
        #expect(run.attemptsToLog.map(\.outcome) == [.skipped, .timedOut])
    }

    @Test func aCheckRunIsNeverForTheLog() {
        var check = lowEDrill()
        check.handle(.played(Pitch(40), onset: s(1), at: s(1.1)))
        #expect(check.attempts.count == 1)
        #expect(check.attemptsToLog.isEmpty)
    }

    @Test func aSweepsAttemptsAreAGroup() {
        var run = DrillKind.allInstances.makeDrill(DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1))
        run.handle(.start(at: s(0)))
        run.handle(.skip(at: s(1)))
        run.handle(.skip(at: s(2)))
        run.handle(.repeat(at: s(3)))   // a new sweep
        run.handle(.skip(at: s(4)))
        #expect(run.attemptsToLog.map(\.group) == [0, 0, 1].map { AttemptGroup(number: $0) })
        #expect(run.attemptsToLog.allSatisfy { $0.facts == nil })
    }

    @Test func otherDrillsAttemptsAreInNoGroup() {
        var run = drill()
        run.handle(.start(at: s(0)))
        run.handle(.skip(at: s(1)))
        #expect(run.attemptsToLog.map(\.group) == [nil])
        #expect(run.attemptsToLog.map(\.facts) == [nil])
    }

    @Test func anAttemptCarriesItsGroupAndFacts() {
        let prompt = NotePrompt(name: .bFlat, string: 1)
        let group = AttemptGroup(number: 4, size: 3, place: 1)
        let facts = AttemptFacts.triad(TriadFacts(triad: Triad(.minor, root: .g), inversion: .first, stringSet: .aDG))
        let attempt = Attempt(prompt: prompt, outcome: .skipped, group: group, facts: facts)
        #expect(attempt.group == group)
        #expect(attempt.facts == facts)
        #expect(attempt != Attempt(prompt: prompt, outcome: .skipped))
    }

    @Test func savedFadeStagesKeepTheirNames() {
        #expect(FadeStage.allCases.map(\.rawValue) == ["shown", "faded", "hidden"])
    }
}
