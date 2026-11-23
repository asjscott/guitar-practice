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
}
