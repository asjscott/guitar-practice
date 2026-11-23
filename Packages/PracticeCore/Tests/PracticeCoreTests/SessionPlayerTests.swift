import Testing
import TheoryCore
import PracticeCore

/// Two 3-minute blocks of the toy drill (E, F, F♯ … on string 6, 15 s each, sounds on every prompt), then one of
/// Note → play it.
private func player(started: Bool = true) -> SessionPlayer {
    var player = SessionPlayer(
        blocks: [SessionBlock(kind: kind("a"), length: s(180)), SessionBlock(kind: kind("b"), length: s(180)),
                 SessionBlock(kind: .notePlayIt, length: s(240))],
        setup: DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1))
    if started { player.handle(.start(at: s(100))) }
    return player
}

/// The first block playing from 102 s.
private func playing() -> SessionPlayer {
    var player = player()
    player.handle(.next(at: s(102)))
    return player
}

@Suite("Session player: stages")
struct SessionStageTests {
    @Test func startShowsTheFirstReadyCardFor5Seconds() {
        var player = player(started: false)
        #expect(player.stage == .idle)
        player.handle(.start(at: s(100)))
        #expect(player.stage == .ready)
        #expect(player.blockIndex == 0)
        #expect(player.readyRemaining == s(5))
        player.handle(.tick(at: s(103)))
        #expect(player.readyRemaining == s(2))
        #expect(player.drill == nil)
        player.handle(.tick(at: s(104.9)))
        #expect(player.stage == .ready)
        player.handle(.tick(at: s(105)))
        #expect(player.stage == .playing)
        #expect(player.drill?.prompt?.noteName == "E")
        #expect(player.drill?.promptStart == s(105.6))
    }

    @Test func spaceStartsTheBlockAtOnce() {
        let player = playing()
        #expect(player.stage == .playing)
        #expect(player.spent(inBlock: 0) == s(0))
    }

    @Test func readyIsNotBlockTimeButIsElapsedTime() {
        var player = playing()
        player.handle(.tick(at: s(112)))
        #expect(player.spent(inBlock: 0) == s(10))
        #expect(player.timeLeft(inBlock: 0) == s(170))
        #expect(player.elapsed == s(12))
        #expect(player.spent(inBlock: 1) == nil)
        #expect(player.timeLeft(inBlock: 1) == s(180))
    }

    @Test func spaceMovesToTheNextBlocksReadyCardAndDropsTheOpenPrompt() {
        var player = playing()
        player.handle(.typed(.g, at: s(110)))       // wrong
        player.handle(.next(at: s(112)))
        #expect(player.stage == .ready)
        #expect(player.blockIndex == 1)
        #expect(player.readyRemaining == s(5))
        #expect(player.attempts(inBlock: 0).isEmpty)
        #expect(player.spent(inBlock: 0) == s(10))
        player.handle(.tick(at: s(114)))
        #expect(player.spent(inBlock: 0) == s(10))
        #expect(player.elapsed == s(14))
    }

    @Test func spaceDropsAPromptEvenWhenItsTimeoutIsDue() {
        var player = playing()
        player.handle(.next(at: s(130)))
        #expect(player.attempts(inBlock: 0).isEmpty)
    }

    @Test func aBlockNeverCutsOff() {
        var player = playing()
        for second in 103...400 { player.handle(.tick(at: s(Double(second)))) }
        #expect(player.stage == .playing)
        #expect(player.blockIndex == 0)
        #expect(player.drill?.isRunning == true)
        #expect(player.timeLeft(inBlock: 0) == s(-118))
        // Later blocks keep their length.
        #expect(player.timeLeft(inBlock: 1) == s(180))
    }

    @Test func spaceInTheLastBlockFinishes() {
        var player = playing()
        for time in [110.0, 111, 120, 121, 130] { player.handle(.next(at: s(time))) }
        #expect(player.stage == .finished)
        #expect(!player.endedEarly)
        #expect(player.elapsed == s(30))
        player.handle(.tick(at: s(200)))
        player.handle(.next(at: s(201)))
        player.handle(.end(at: s(202)))
        #expect(player.stage == .finished)
        #expect(!player.endedEarly)
        #expect(player.elapsed == s(30))
    }

    @Test func endingEarlyStopsTheBlockAndDropsThePrompt() {
        var player = playing()
        player.handle(.end(at: s(110)))
        #expect(player.stage == .finished)
        #expect(player.endedEarly)
        #expect(player.drill?.isRunning != true)
        #expect(player.elapsed == s(10))
        #expect(player.spent(inBlock: 0) == s(8))
    }

    @Test func nothingHappensBeforeStart() {
        var player = player(started: false)
        player.handle(.next(at: s(1)))
        player.handle(.tick(at: s(2)))
        player.handle(.end(at: s(3)))
        #expect(player.stage == .idle)
        #expect(player.elapsed == .zero)
    }

    @Test func noBlocksFinishesAtOnce() {
        var player = SessionPlayer(blocks: [], setup: DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1))
        player.handle(.start(at: s(0)))
        #expect(player.stage == .finished)
    }
}

@Suite("Session player: drills")
struct SessionDrillTests {
    @Test func playedAndTypedAnswersReachTheDrill() {
        var player = playing()
        player.handle(.played(Pitch(40), onset: s(104.6), at: s(104.7)))
        #expect(player.drill?.phase == .correct(FretboardLocation(string: 0, fret: 0)))
        player.handle(.tick(at: s(106)))
        player.handle(.typed(.f, at: s(108.6)))
        #expect(player.attempts(inBlock: 0).map(\.responseTime) == [s(2), s(2)])
    }

    @Test func skipAndRepeatReachTheDrill() {
        var player = playing()
        player.handle(.skip(at: s(103)))
        #expect(player.attempts(inBlock: 0).map(\.outcome) == [.skipped])
        _ = player.takeSounds()
        player.handle(.repeat(at: s(104)))
        #expect(player.takeSounds().map(\.at) == [s(104)])
    }

    @Test func theDrillsSoundRequestsComeOutOnceAndNoneOutsideABlock() {
        var player = player()
        #expect(player.takeSounds().isEmpty)
        player.handle(.next(at: s(102)))
        #expect(player.takeSounds().map(\.at) == [s(102)])
        #expect(player.takeSounds().isEmpty)
        player.handle(.skip(at: s(103)))
        player.handle(.next(at: s(103)))
        #expect(player.takeSounds().isEmpty)
    }

    @Test func nothingPlayedOnTheReadyCardCounts() {
        var player = player()
        player.handle(.played(Pitch(40), onset: s(101), at: s(101.1)))
        player.handle(.typed(.e, at: s(101.5)))
        player.handle(.skip(at: s(101.6)))
        player.handle(.tick(at: s(105)))
        #expect(player.drill?.phase == .waiting)
        // Sounding before the block began, detected after.
        player.handle(.played(Pitch(40), onset: s(104.95), at: s(105.1)))
        #expect(player.drill?.attempts.isEmpty == true)
    }

    @Test func aNoteDetectedBeforeTheLastTickLeavesTheClockAlone() {
        var player = playing()
        player.handle(.tick(at: s(110)))
        player.handle(.played(Pitch(43), onset: s(109.8), at: s(109.9)))
        player.handle(.tick(at: s(111)))
        #expect(player.spent(inBlock: 0) == s(9))
        #expect(player.elapsed == s(11))
    }

    @Test func eachBlockUsesTheSetupWithItsOwnSeed() {
        var options = DrillOptions()
        options.frets = 3...15
        let setup = DrillSetup(fretboard: Fretboard(tuning: .standard, capo: 3), options: options, key: .major(.bFlat),
                               weighting: NoteWeighting(preferred: [PitchClass(10)], share: 0.7), seed: 9)
        var player = SessionPlayer(blocks: Array(repeating: SessionBlock(kind: .notePlayIt, length: s(180)), count: 2), setup: setup)
        player.handle(.start(at: s(0)))
        player.handle(.next(at: s(1)))
        let first = player.drill?.setup
        player.handle(.next(at: s(2)))
        player.handle(.next(at: s(3)))
        let second = player.drill?.setup
        #expect(first?.options == options)
        #expect(first?.key == .major(.bFlat))
        #expect(first?.weighting == setup.weighting)
        #expect(first?.fretboard == setup.fretboard)
        #expect(first?.seed != second?.seed)
    }
}

@Suite("Session summary")
struct SessionSummaryTests {
    @Test func figuresPerBlockAndTheSlowestOverall() {
        var player = playing()
        // Block a: E after a wrong note in 3 s, F in 1 s, F♯ skipped.
        player.handle(.typed(.g, at: s(103)))
        player.handle(.typed(.e, at: s(105.6)))
        player.handle(.tick(at: s(106)))
        player.handle(.typed(.f, at: s(107.6)))
        player.handle(.tick(at: s(108)))
        player.handle(.skip(at: s(109)))
        player.handle(.next(at: s(110)))
        // Block b: one timeout and nothing answered.
        player.handle(.next(at: s(112)))
        player.handle(.tick(at: s(127.8)))
        player.handle(.next(at: s(130)))
        player.handle(.end(at: s(131)))      // on the third block's Ready card

        let summary = player.summary
        #expect(summary.totalTime == s(31))
        #expect(summary.blocks.map(\.kind.id) == ["a", "b"])
        #expect(summary.blocks.map(\.time) == [s(8), s(18)])
        let a = summary.blocks[0].stats
        #expect(a.prompts == 2)
        #expect(a.firstTryAccuracy == 0.5)
        #expect(a.medianResponseTime == s(2))
        #expect(a.skips == 1)
        #expect(summary.blocks[0].speedText == "2.00 s")
        let b = summary.blocks[1].stats
        #expect(b.prompts == 1)
        #expect(b.firstTryAccuracy == 0)
        #expect(summary.blocks[1].speedText == nil)
        #expect(summary.slowest(2).map { $0.summaryLine(in: .standard) }
                == ["E on string 6 (E) — timed out", "E on string 6 (E) — 3.00 s · typed G first"])
        #expect(!summary.hasNoAttempts)
    }

    @Test func noAttempts() {
        var player = playing()
        player.handle(.end(at: s(110)))
        #expect(player.summary.hasNoAttempts)
        #expect(player.summary.blocks.map(\.kind.id) == ["a"])
        #expect(player.summary.blocks[0].stats.firstTryAccuracy == nil)
    }

    @Test func endedOnTheFirstReadyCard() {
        var player = player()
        player.handle(.end(at: s(103)))
        #expect(player.summary.blocks.isEmpty)
        #expect(player.summary.totalTime == s(3))
    }

    @Test func minutesAndSeconds() {
        #expect([0, 5, 59.9, 60, 225, 3600].map { clockText(s($0)) } == ["0:00", "0:05", "0:59", "1:00", "3:45", "60:00"])
        #expect(clockText(s(0.1), rounding: .up) == "0:01")
        #expect(clockText(s(-3)) == "0:00")
    }
}
