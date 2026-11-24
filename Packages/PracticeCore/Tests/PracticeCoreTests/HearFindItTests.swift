import Testing
import TheoryCore
import PracticeCore

private typealias Hear = PromptDrill<HearFindItRules>

/// Every note on one string (string 6 unless given), all notes.
private func hear(_ tuning: Tuning = .standard, capo: Int = 0, frets: ClosedRange<Int> = 0...12, string: Int? = 0,
                  notes: DrillOptions.Notes = .all, key: Key? = nil, seed: UInt64 = 1) -> Hear {
    var options = DrillOptions()
    options.notes = notes
    options.frets = frets
    options.strings = string.map { [$0] }
    return Hear(setup: DrillSetup(fretboard: Fretboard(tuning: tuning, capo: capo), options: options, key: key, seed: seed))
}

/// Started at 0 and asking for F2 (41) at fret 1 of string 6, its only target. Its timer runs from 0.6 s.
private func lowF() -> Hear {
    var drill = hear(frets: 0...1)
    drill.handle(.start(at: s(0)))
    return drill
}

private func targets(_ drill: Hear, count: Int = 300) -> [FretboardLocation] {
    var drill = drill
    drill.handle(.start(at: s(0)))
    return (0..<count).compactMap { _ in
        defer { drill.handle(.skip(at: s(0))) }
        return drill.prompt?.target
    }
}

@Suite("Hear → find it")
struct HearFindItTests {
    @Test func isOfferedWithSoundAndReplay() {
        #expect(DrillKind.all.contains(.hearFindIt))
        #expect(DrillKind.hearFindIt.id == "hearFindIt")
        #expect(DrillKind.hearFindIt.needsSound)
        #expect(DrillKind.hearFindIt.hidesNote)
        #expect(DrillKind.hearFindIt.repeatTitle == "Replay")
    }

    // MARK: Sound

    @Test func playsTheOpenStringThenTheTarget() {
        var drill = lowF()
        #expect(drill.takeSounds() == [DrillSoundRequest(tones: [
            DrillTone(pitch: Pitch(40), duration: .milliseconds(600)),
            DrillTone(pitch: Pitch(41), duration: .milliseconds(600)),
        ], at: s(0))])
    }

    @Test func withACapoTheOpenStringSoundsAtTheCapo() {
        // Drop D, capo 2: string 6 sounds E2 (40); fret 3 is F2.
        var drill = hear(TuningPreset.dropD.tuning, capo: 2, frets: 0...3)
        drill.handle(.start(at: s(0)))
        #expect(drill.takeSounds().first?.tones.map(\.pitch) == [Pitch(40), Pitch(41)])
        #expect(drill.prompt?.target == FretboardLocation(string: 0, fret: 3))
    }

    @Test func replayPlaysAgainWithoutResettingTheTimer() {
        var drill = lowF()
        let first = drill.takeSounds()
        drill.handle(.repeat(at: s(5)))
        let again = drill.takeSounds()
        #expect(again.map(\.tones) == first.map(\.tones))
        #expect(again.map(\.at) == [s(5)])
        drill.handle(.played(Pitch(41), onset: s(7.6), at: s(7.7)))
        #expect(drill.attempts.map(\.responseTime) == [s(7)])
    }

    @Test func pausingDropsThePromptAndResumingPlaysAnother() {
        var drill = hear()
        drill.handle(.start(at: s(0)))
        let old = drill.prompt
        drill.handle(.pause(at: s(0.1)))
        #expect(drill.takeSounds().isEmpty)
        drill.handle(.resume(at: s(9)))
        #expect(drill.prompt != old)
        #expect(drill.takeSounds().map(\.at) == [s(9)])
        #expect(drill.promptStart == s(9.6))
    }

    // MARK: Timing

    @Test func theTimerRunsFromTheTargetBeingHeard() {
        var drill = lowF()
        drill.handle(.soundStarted(at: s(0.01), latency: s(0.2)))
        #expect(drill.promptStart == s(0.81))
        drill.handle(.played(Pitch(41), onset: s(2.81), at: s(2.9)))
        #expect(drill.attempts.map(\.responseTime) == [s(2)])
    }

    @Test func aReplayDoesNotMoveTheTimer() {
        var drill = lowF()
        drill.handle(.soundStarted(at: s(0), latency: s(0.2)))
        drill.handle(.repeat(at: s(5)))
        drill.handle(.soundStarted(at: s(5), latency: s(0.2)))
        #expect(drill.promptStart == s(0.8))
    }

    @Test func aSoundHeardLateInASessionMovesTheTimer() {
        var player = SessionPlayer(blocks: [SessionBlock(kind: .hearFindIt, length: s(180))],
                                   setup: DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1))
        player.handle(.start(at: s(0)))
        player.handle(.next(at: s(1)))
        for request in player.takeSounds() {
            player.handle(.soundStarted(.tones(request.tones), at: s(1), latency: s(0.25)))
        }
        #expect(player.drill?.promptStart == s(1.85))
    }

    // MARK: Answers

    @Test func onlyTheExactPitchIsRight() {
        var drill = lowF()
        drill.handle(.played(Pitch(53), onset: s(2), at: s(2.1)))
        #expect(drill.display?.feedback == "Too high")
        drill.handle(.played(Pitch(29), onset: s(2.5), at: s(2.6)))
        #expect(drill.display?.feedback == "Too low")
        drill.handle(.played(Pitch(41), onset: s(3.6), at: s(3.7)))
        #expect(drill.phase == .correct(FretboardLocation(string: 0, fret: 1)))
        #expect(drill.attempts.map(\.responseTime) == [s(3)])
        #expect(drill.attempts.map(\.wrongAnswers) == [[.pitch(Pitch(53)), .pitch(Pitch(29))]])
        #expect(drill.attempts.map(\.firstRight) == [false])
    }

    @Test func aNoteBeforeTheTargetSoundsDoesNotCount() {
        var drill = lowF()
        drill.handle(.played(Pitch(41), onset: s(0.5), at: s(0.7)))
        #expect(drill.phase == .waiting)
    }

    @Test func timesOutFifteenSecondsAfterTheTargetStarts() {
        var drill = lowF()
        #expect(drill.timeLimit == s(15))
        drill.handle(.tick(at: s(15.79)))
        #expect(drill.phase == .waiting)
        drill.handle(.tick(at: s(15.8)))
        #expect(drill.phase == .timedOut)
    }

    @Test func typedNamesAreIgnored() {
        var drill = lowF()
        drill.handle(.typed(.f, at: s(2)))
        #expect(drill.phase == .waiting)
    }

    // MARK: Display

    @Test func theNoteIsHiddenAndTheStringNamedAndLitUntilTheEnd() {
        var drill = lowF()
        #expect(drill.display?.headline == "♪")
        #expect(drill.display?.subline == "on string 6 (E)")
        #expect(drill.display?.highlightedStrings == [0])
        #expect(drill.display?.markers == [])
        #expect(drill.display?.feedback == "Listening…")

        drill.handle(.played(Pitch(43), onset: s(2), at: s(2.1)))
        #expect(drill.display?.headline == "♪")
        #expect(drill.display?.markers == [])
        #expect(drill.display?.result == .wrong)

        drill.handle(.played(Pitch(41), onset: s(3.6), at: s(3.7)))
        #expect(drill.display?.headline == "F")
        #expect(drill.display?.feedback == "Fret 1 · 3.00 s")
        #expect(drill.display?.markers == [.init(location: FretboardLocation(string: 0, fret: 1), label: "F", isAnswer: true)])
    }

    @Test func aTimeoutShowsTheNoteAndFret() {
        var drill = lowF()
        drill.handle(.tick(at: s(15.8)))
        #expect(drill.display?.headline == "F")
        #expect(drill.display?.subline == "on string 6 (E) · fret 1")
        #expect(drill.display?.markers == [.init(location: FretboardLocation(string: 0, fret: 1), label: "F", isAnswer: false)])
    }

    @Test func theNoteIsSpelledInTheKey() {
        var drill = hear(frets: 2...2, key: .major(.dFlat))
        drill.handle(.start(at: s(0)))
        drill.handle(.tick(at: s(15.8)))
        #expect(drill.display?.headline == "G♭")
    }

    // MARK: Targets

    @Test func targetsAreOneToTwelveFretsUp() {
        #expect(Set(targets(hear()).map(\.fret)) == Set(1...12))
        #expect(Set(targets(hear(frets: 0...22)).map(\.fret)) == Set(1...12))
        #expect(Set(targets(hear(capo: 5, frets: 0...22)).map(\.fret)) == Set(6...17))
        #expect(Set(targets(hear(capo: 12, frets: 0...22)).map(\.fret)) == Set(13...22))
        #expect(Set(targets(hear(notes: .naturals)).map(\.fret)) == [1, 3, 5, 7, 8, 10, 12])
    }

    @Test(arguments: [TuningPreset.standard, .dropD, .dadgad, .openG], [0, 3])
    func targetsStayInRangeInEveryTuning(preset: TuningPreset, capo: Int) {
        let found = targets(hear(preset.tuning, capo: capo, string: nil))
        #expect(Set(found.map(\.string)) == Set(0...5))
        #expect(found.allSatisfy { (capo + 1...12).contains($0.fret) })
        #expect(zip(found, found.dropFirst()).allSatisfy { $0 != $1 })
    }

    @Test func nothingToPrompt() {
        #expect(hear().nothingToPromptReason == nil)
        // Only the open string is left.
        #expect(hear(capo: 12).nothingToPromptReason == "The capo leaves no frets to play in this range.")
        // String 6, capo 1, frets 0–2: only F♯ is above the capo.
        #expect(hear(capo: 1, frets: 0...2, notes: .naturals).nothingToPromptReason
                == "No natural notes in these frets and strings. Choose All notes.")
    }
}
