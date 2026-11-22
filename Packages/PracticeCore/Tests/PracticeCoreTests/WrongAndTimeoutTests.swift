import Testing
import TheoryCore
import PracticeCore

@Suite("Wrong notes and timeouts")
struct WrongAndTimeoutTests {
    @Test func wrongThenRight() {
        var drill = lowEDrill()
        drill.handle(.played(Pitch(43), onset: s(0.5), at: s(0.6)))   // G
        #expect(drill.phase == .wrong(PitchClass(7)))
        #expect(drill.prompt?.pitchClass == PitchClass(4))
        drill.handle(.played(Pitch(41), onset: s(1.0), at: s(1.1)))   // F
        #expect(drill.phase == .wrong(PitchClass(5)))
        drill.handle(.played(Pitch(40), onset: s(1.7), at: s(1.8)))   // E
        #expect(drill.phase == .correct(FretboardLocation(string: 0, fret: 0)))
        #expect(drill.attempts == [Attempt(prompt: NotePrompt(pitchClass: PitchClass(4), string: 0,
                                                              target: FretboardLocation(string: 0, fret: 0)),
                                           firstRight: false, responseTime: s(1.7),
                                           wrongNotes: [PitchClass(7), PitchClass(5)],
                                           location: FretboardLocation(string: 0, fret: 0))])
    }

    @Test func wrongOctaveIsWrong() {
        // E4 is not on string 6 within frets 0–12.
        var drill = lowEDrill()
        drill.handle(.played(Pitch(64), onset: s(0.5), at: s(0.6)))
        #expect(drill.phase == .wrong(PitchClass(4)))
        #expect(drill.attempts.isEmpty)
    }

    @Test func timeoutAt10sRevealsTheRightLocations() {
        var drill = lowEDrill()
        drill.handle(.played(Pitch(43), onset: s(2), at: s(2.1)))
        drill.handle(.tick(at: s(9.95)))
        #expect(drill.phase == .wrong(PitchClass(7)))
        #expect(drill.timeRemaining(at: s(9.95)) == s(0.05))
        drill.handle(.tick(at: s(10.2)))
        #expect(drill.phase == .timedOut)
        #expect(drill.revealedLocations == [FretboardLocation(string: 0, fret: 0), FretboardLocation(string: 0, fret: 12)])
        #expect(drill.attempts.count == 1)
        #expect(drill.attempts[0].timedOut)
        #expect(drill.attempts[0].responseTime == nil)
        #expect(drill.attempts[0].firstRight == false)
        #expect(drill.attempts[0].wrongNotes == [PitchClass(7)])
        #expect(drill.attempts[0].location == nil)
    }

    @Test func aNoteDuringTheRevealIsIgnoredThenTheNextPromptFollows() {
        var drill = lowEDrill()
        drill.handle(.tick(at: s(10.2)))
        drill.handle(.played(Pitch(40), onset: s(10.5), at: s(10.6)))
        #expect(drill.phase == .timedOut)
        #expect(drill.attempts.count == 1)
        drill.handle(.tick(at: s(10.2 + 1.8)))
        #expect(drill.phase == .waiting)
        #expect(drill.prompt?.target == FretboardLocation(string: 0, fret: 1))
        #expect(drill.revealedLocations.isEmpty)
    }

    @Test func revealedLocationsStayInTheFretRange() {
        var drill = lowEDrill(frets: 0...5)
        drill.handle(.tick(at: s(10.2)))
        #expect(drill.revealedLocations == [FretboardLocation(string: 0, fret: 0)])
    }
}

@Suite("Timing")
struct TimingTests {
    @Test func pauseStopsTheClockAndResumeRestartsThePromptTimer() {
        var drill = lowEDrill()
        drill.handle(.tick(at: s(4)))
        drill.handle(.pause(at: s(4)))
        #expect(drill.phase == .paused)
        // Paused far past the timeout: nothing times out, notes are ignored.
        drill.handle(.tick(at: s(30)))
        drill.handle(.played(Pitch(40), onset: s(31), at: s(31.1)))
        #expect(drill.phase == .paused)
        #expect(drill.attempts.isEmpty)
        drill.handle(.resume(at: s(40)))
        #expect(drill.phase == .waiting)
        #expect(drill.timeRemaining(at: s(40)) == s(10))
        drill.handle(.tick(at: s(49.9)))
        #expect(drill.phase == .waiting)
        drill.handle(.played(Pitch(40), onset: s(41.25), at: s(41.3)))
        #expect(drill.attempts.first?.responseTime == s(1.25))
    }

    @Test func resumeKeepsTheWrongNotesSoFar() {
        var drill = lowEDrill()
        drill.handle(.played(Pitch(43), onset: s(1), at: s(1.1)))
        drill.handle(.pause(at: s(2)))
        drill.handle(.resume(at: s(5)))
        #expect(drill.phase == .wrong(PitchClass(7)))
        drill.handle(.played(Pitch(40), onset: s(6), at: s(6.1)))
        #expect(drill.attempts.first?.wrongNotes == [PitchClass(7)])
        #expect(drill.attempts.first?.firstRight == false)
        #expect(drill.attempts.first?.responseTime == s(1))
    }

    @Test func pausedDuringTheRightAnswerResumesOnTheNextPrompt() {
        var drill = lowEDrill()
        drill.handle(.played(Pitch(40), onset: s(1), at: s(1.1)))
        drill.handle(.pause(at: s(1.2)))
        drill.handle(.tick(at: s(3)))
        #expect(drill.phase == .paused)
        drill.handle(.resume(at: s(5)))
        #expect(drill.phase == .waiting)
        #expect(drill.prompt?.target == FretboardLocation(string: 0, fret: 1))
        #expect(drill.promptStart == s(5))
    }

    @Test func aRingingNoteFromBeforeThePromptIsIgnored() {
        var drill = lowEDrill()
        drill.handle(.played(Pitch(40), onset: s(1), at: s(1.1)))
        drill.handle(.tick(at: s(1.5)))
        #expect(drill.promptStart == s(1.5))
        // F (the new prompt) with an onset before the prompt appeared, detected after.
        drill.handle(.played(Pitch(41), onset: s(1.45), at: s(1.55)))
        #expect(drill.phase == .waiting)
        #expect(drill.attempts.count == 1)
        drill.handle(.played(Pitch(41), onset: s(2), at: s(2.1)))
        #expect(drill.attempts.count == 2)
        #expect(drill.attempts[1].responseTime == s(0.5))
    }

    @Test func aRightNoteWithAnOnsetBeforeTheTimeoutCountsEvenIfDetectedAfter() {
        var drill = lowEDrill()
        drill.handle(.played(Pitch(40), onset: s(9.95), at: s(10.05)))
        #expect(drill.phase == .correct(FretboardLocation(string: 0, fret: 0)))
        #expect(drill.attempts.first?.responseTime == s(9.95))
    }

    @Test func aTickJustAfterTheTimeoutWaitsForANoteStillBeingDetected() {
        // Played at 9.9 s, but detection takes ~130 ms: a tick at 10.0 s mustn't time it out first.
        var drill = lowEDrill()
        drill.handle(.tick(at: s(10)))
        drill.handle(.tick(at: s(10.1)))
        #expect(drill.phase == .waiting)
        #expect(drill.timeRemaining(at: s(10.1)) == .zero)
        drill.handle(.played(Pitch(40), onset: s(9.9), at: s(10.13)))
        #expect(drill.phase == .correct(FretboardLocation(string: 0, fret: 0)))
        #expect(drill.attempts.first?.responseTime == s(9.9))
    }

    @Test func aRightNoteWithAnOnsetAfterTheTimeoutDoesNotCount() {
        var drill = lowEDrill()
        drill.handle(.played(Pitch(40), onset: s(10.05), at: s(10.15)))
        #expect(drill.phase == .timedOut)
        #expect(drill.attempts.first?.timedOut == true)
    }

    @Test func theTimeoutHappensOnceTheDetectionGraceIsOver() {
        var drill = lowEDrill()
        drill.handle(.tick(at: NotePlayItDrill.timeout + NotePlayItDrill.detectionGrace))
        #expect(drill.phase == .timedOut)
    }

    @Test func stopEndsTheRunAndKeepsTheAttempts() {
        var drill = lowEDrill()
        drill.handle(.played(Pitch(40), onset: s(1), at: s(1.1)))
        drill.handle(.tick(at: s(2)))
        drill.handle(.stop(at: s(3)))
        #expect(drill.phase == .idle)
        #expect(!drill.isRunning)
        #expect(drill.prompt == nil)
        #expect(drill.attempts.count == 1)
        drill.handle(.tick(at: s(20)))
        #expect(drill.attempts.count == 1)
    }

    @Test func startClearsTheLastRun() {
        var drill = lowEDrill()
        drill.handle(.played(Pitch(40), onset: s(1), at: s(1.1)))
        drill.handle(.stop(at: s(2)))
        drill.handle(.start(at: s(3)))
        #expect(drill.attempts.isEmpty)
        #expect(drill.phase == .waiting)
        #expect(drill.promptStart == s(3))
    }
}
