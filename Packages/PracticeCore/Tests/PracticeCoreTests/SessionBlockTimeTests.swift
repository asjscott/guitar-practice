import Testing
import TheoryCore
import PracticeCore

/// 3-minute blocks, the first playing from 102 s: 30 s left at 252 s, planned end at 282 s. By default both are the
/// toy drill; with a capo of 1 it goes straight on from prompt to prompt, as a sweep does.
private func playing(capo: Int = 0, hasSound: Bool = true, kinds: [DrillKind] = [kind("a"), kind("b")]) -> SessionPlayer {
    var player = SessionPlayer(blocks: kinds.map { SessionBlock(kind: $0, length: s(180)) },
                               setup: DrillSetup(fretboard: Fretboard(tuning: .standard, capo: capo), seed: 1),
                               hasSound: hasSound)
    player.handle(.start(at: s(100)))
    player.handle(.next(at: s(102)))
    return player
}

extension SessionPlayer {
    /// A fresh prompt at `time`, and no chime.
    fileprivate mutating func skip(at time: Double) {
        handle(.skip(at: s(time)))
        #expect(takeChime() == nil)
    }

    /// The right answer to the prompt that is up.
    fileprivate mutating func answer(at time: Double) {
        if let name = drill?.prompt?.name { handle(.typed(name, at: s(time))) }
    }

    /// As the app does: plays whatever chime there is.
    fileprivate mutating func playChime(at time: Double) -> AppSound? {
        let chime = takeChime()
        if let chime { handle(.soundStarted(chime, at: s(time), latency: s(0.1))) }
        return chime
    }
}

@Suite("Session player: chimes")
struct SessionChimeTests {
    @Test func inAGapTheyAreOnTime() {
        var player = playing()
        player.skip(at: 250)
        player.answer(at: 251.8)
        #expect(player.takeChime() == nil)
        player.handle(.tick(at: s(252)))
        #expect(player.takeChime() == .chime)
        #expect(player.takeChime() == nil)
        player.skip(at: 280)
        player.answer(at: 281.8)
        player.handle(.tick(at: s(282)))
        #expect(player.takeChime() == .softChime)
        for time in stride(from: 283.0, to: 500, by: 1) { player.handle(.tick(at: s(time))) }
        #expect(player.takeChime() == nil)
    }

    @Test func theyWaitForTheNextGap() {
        var player = playing()
        player.skip(at: 250)
        player.handle(.tick(at: s(252)))
        player.handle(.typed(.b, at: s(253)))       // wrong: the prompt stays
        #expect(player.takeChime() == nil)
        player.answer(at: 254)
        #expect(player.takeChime() == .chime)
        player.skip(at: 281)
        player.handle(.tick(at: s(283)))
        #expect(player.takeChime() == nil)
        player.handle(.tick(at: s(296.9)))
        #expect(player.drill?.phase == .timedOut)
        #expect(player.takeChime() == .softChime)
    }

    @Test func theNextPromptWaitsForTheChimeToEnd() {
        var player = playing()
        player.skip(at: 250)
        player.handle(.tick(at: s(252)))
        player.answer(at: 254)
        let answered = player.drill?.phase
        #expect(player.playChime(at: 254) == .chime)     // until 254 + 0.1 + 0.9 + 0.3
        player.handle(.tick(at: s(255.2)))
        player.handle(.typed(.c, at: s(255.2)))
        #expect(player.drill?.phase == answered)
        player.handle(.tick(at: s(255.4)))
        #expect(player.drill?.phase == .waiting)
        #expect(player.drill?.promptStart == s(256))
        #expect(player.spent(inBlock: 0) == s(153.4))
    }

    @Test func withinASweepTheyComeBetweenLocationsAndTheNextIsTimedFromTheirEnd() {
        var player = playing(capo: 1)
        player.skip(at: 250)
        player.handle(.tick(at: s(252)))
        #expect(player.takeChime() == nil)
        player.answer(at: 254)
        let count = player.attempts(inBlock: 0).count
        #expect(player.playChime(at: 254) == .chime)
        // The next location stays on show, but isn't timed.
        let next = player.display
        #expect(next != nil)
        #expect(player.drill?.timeRemaining(at: s(254.5)) == nil)
        player.handle(.tick(at: s(255)))
        #expect(player.display == next)
        player.handle(.tick(at: s(255.4)))
        #expect(player.drill?.phase == .waiting)
        #expect(player.drill?.promptStart == s(255.4))
        #expect(player.attempts(inBlock: 0).count == count)
    }

    @Test func skippingMakesAGap() {
        var player = playing()
        player.skip(at: 250)
        player.handle(.tick(at: s(252)))
        _ = player.takeSounds()
        player.handle(.skip(at: s(253)))
        let count = player.attempts(inBlock: 0).count
        #expect(player.playChime(at: 253) == .chime)
        #expect(player.takeSounds().isEmpty)
        #expect(player.display == nil)
        player.handle(.tick(at: s(254.4)))
        #expect(player.drill?.promptStart == s(255))
        #expect(player.takeSounds().map(\.at) == [s(254.4)])
        #expect(player.attempts(inBlock: 0).count == count)
    }

    @Test func heldThroughAPauseForResume() {
        var player = playing()
        player.skip(at: 250)
        player.handle(.tick(at: s(252)))
        player.handle(.pause(at: s(253)))
        player.handle(.tick(at: s(300)))
        #expect(player.takeChime() == nil)
        _ = player.takeSounds()
        player.handle(.resume(at: s(310)))
        #expect(player.stage == .playing)
        #expect(player.playChime(at: 310) == .chime)
        #expect(player.drill?.prompt == nil)
        player.handle(.tick(at: s(311)))
        #expect(player.drill?.prompt == nil)
        player.handle(.tick(at: s(311.4)))
        #expect(player.drill?.promptStart == s(312))
        #expect(player.takeSounds().map(\.at) == [s(311.4)])
    }

    @Test func aTimeoutFoundByPausingIsNoGap() {
        var player = playing()
        player.skip(at: 250)
        player.handle(.pause(at: s(270)))
        #expect(player.takeChime() == nil)
        player.handle(.resume(at: s(280)))
        #expect(player.takeChime() == .chime)
    }

    @Test func pausedTimeIsNotCountedTowardsThem() {
        var player = playing()
        player.skip(at: 245)
        player.handle(.pause(at: s(247)))       // 35 s left
        player.handle(.resume(at: s(400)))
        #expect(player.takeChime() == nil)
        player.handle(.tick(at: s(404)))
        player.answer(at: 404.5)
        #expect(player.takeChime() == nil)
        player.handle(.skip(at: s(405.1)))
        #expect(player.takeChime() == .chime)
    }

    @Test func pausingWhileTheChimeSoundsDoesNotRepeatIt() {
        var player = playing(capo: 1)
        player.skip(at: 250)
        player.handle(.tick(at: s(252)))
        player.answer(at: 254)
        #expect(player.playChime(at: 254) == .chime)
        player.handle(.pause(at: s(254.5)))
        #expect(player.display == nil)
        player.handle(.resume(at: s(260)))
        #expect(player.takeChime() == nil)
        #expect(player.drill?.phase == .waiting)
    }

    @Test func aChimeStillHeldWhenTheBlockEndsIsDropped() {
        var player = playing()
        player.skip(at: 250)
        player.handle(.tick(at: s(252)))
        player.handle(.next(at: s(253)))
        player.handle(.next(at: s(254)))
        player.skip(at: 256)
    }

    @Test func onlyTheLaterOfTwoHeldChimesSounds() {
        var player = playing()
        player.skip(at: 250)
        player.handle(.skip(at: s(290)))
        #expect(player.takeChime() == .softChime)
        player.skip(at: 291)
    }

    @Test func withoutSoundAChimeIsStillGivenToFlashAndNothingWaitsForIt() {
        var player = playing(capo: 1, hasSound: false)
        player.skip(at: 250)
        player.handle(.tick(at: s(252)))
        player.answer(at: 254)
        #expect(player.takeChime() == .chime)
        #expect(player.drill?.phase == .waiting)
        #expect(player.drill?.promptStart == s(254))
    }

    @Test func withoutSoundAChimeHeldThroughAPauseFlashesOnResume() {
        var player = playing(hasSound: false)
        player.skip(at: 250)
        player.handle(.pause(at: s(253)))
        #expect(player.takeChime() == nil)
        player.handle(.resume(at: s(260)))
        #expect(player.takeChime() == .chime)
        #expect(player.drill?.phase == .waiting)
    }
}

@Suite("Session player: extending and overtime")
struct SessionExtendTests {
    @Test func extendAdds2MinutesToThisBlockOnly() {
        var player = playing()
        player.handle(.extend(at: s(112)))
        #expect(player.timeLeft(inBlock: 0) == s(290))
        #expect(player.length(ofBlock: 0) == s(300))
        #expect(player.timeLeft(inBlock: 1) == s(180))
        player.handle(.extend(at: s(113)))
        #expect(player.timeLeft(inBlock: 0) == s(409))
        player.handle(.next(at: s(114)))
        #expect(player.length(ofBlock: 1) == s(180))
    }

    @Test func extendMovesBothChimes() {
        var player = playing()
        player.handle(.extend(at: s(200)))
        player.skip(at: 371)
        player.skip(at: 371.9)                  // 30.1 s left
        player.handle(.skip(at: s(372)))
        #expect(player.takeChime() == .chime)
        player.skip(at: 401.9)
        player.handle(.skip(at: s(402)))
        #expect(player.takeChime() == .softChime)
    }

    @Test func extendAfterTheFirstChimeBringsItAgain() {
        var player = playing()
        player.handle(.skip(at: s(252)))
        #expect(player.takeChime() == .chime)
        player.handle(.extend(at: s(260)))
        player.handle(.tick(at: s(261)))
        player.skip(at: 371)
        player.handle(.skip(at: s(372)))
        #expect(player.takeChime() == .chime)
    }

    @Test func extendDropsAHeldChime() {
        var player = playing()
        player.skip(at: 250)
        player.handle(.tick(at: s(252)))
        player.handle(.extend(at: s(253)))
        player.skip(at: 254)
    }

    @Test func extendInOvertime() {
        var player = playing()
        player.handle(.tick(at: s(292)))
        _ = player.takeChime()
        #expect(player.timeLeft(inBlock: 0) == s(-10))
        player.handle(.extend(at: s(292)))
        #expect(player.timeLeft(inBlock: 0) == s(110))
        player.handle(.tick(at: s(293)))
        player.handle(.skip(at: s(373)))
        #expect(player.takeChime() == .chime)
        player.handle(.skip(at: s(402)))
        #expect(player.takeChime() == .softChime)
        player.handle(.tick(at: s(502)))
        player.handle(.extend(at: s(502)))      // 20 s left: too late for the first chime
        player.handle(.tick(at: s(503)))
        player.skip(at: 510)
        player.handle(.skip(at: s(522)))
        #expect(player.takeChime() == .softChime)
        player.handle(.tick(at: s(700)))
        player.handle(.extend(at: s(700)))      // not enough to leave overtime
        #expect(player.timeLeft(inBlock: 0) == s(-58))
    }

    @Test func onlyWhilePlaying() {
        var player = playing()
        player.handle(.pause(at: s(103)))
        player.handle(.extend(at: s(104)))
        player.handle(.resume(at: s(105)))
        player.handle(.next(at: s(106)))
        player.handle(.extend(at: s(107)))
        player.handle(.end(at: s(108)))
        player.handle(.extend(at: s(109)))
        #expect((0...1).map { player.length(ofBlock: $0) } == [s(180), s(180)])
    }

    @Test func projectedFinish() {
        var player = playing()
        // This block, then the next one's Ready card and block.
        #expect(player.timeToFinish == s(180 + 5 + 180))
        player.handle(.extend(at: s(112)))
        #expect(player.timeToFinish == s(290 + 5 + 180))
        player.handle(.tick(at: s(422)))
        #expect(player.timeLeft(inBlock: 0) == s(-20))
        #expect(player.timeToFinish == s(5 + 180))
        player.handle(.next(at: s(422)))
        player.handle(.tick(at: s(424)))
        #expect(player.timeToFinish == s(3 + 180))
        player.handle(.pause(at: s(424)))
        player.handle(.tick(at: s(500)))
        #expect(player.timeToFinish == s(5 + 180))      // the Ready card counts down afresh
        player.handle(.resume(at: s(500)))
        player.handle(.next(at: s(501)))
        player.handle(.next(at: s(502)))
        #expect(player.timeToFinish == .zero)
    }
}

@Suite("Session player: the output failing")
struct SessionOutputTests {
    private let hear = kind("hear", needsSound: true)

    @Test func failingMidBlockPauses() {
        for first in [hear, kind("a")] {
            var player = playing(kinds: [first, kind("b")])
            player.handle(.output(works: false, at: s(112)))
            #expect(player.stage == .paused)
            #expect(player.spent(inBlock: 0) == s(10))
        }
    }

    @Test func aBlockThatDoesNotNeedSoundResumes() {
        var player = playing()
        player.handle(.output(works: false, at: s(112)))
        player.handle(.resume(at: s(120)))
        #expect(player.stage == .playing)
        #expect(player.blockIndex == 0)
        // Told again, it doesn't pause again.
        player.handle(.output(works: false, at: s(121)))
        #expect(player.stage == .playing)
    }

    @Test func oneThatNeedsSoundIsLeftOnResume() {
        var player = playing(kinds: [hear, kind("b")])
        player.handle(.skip(at: s(110)))
        player.handle(.output(works: false, at: s(112)))
        player.handle(.resume(at: s(120)))
        #expect(player.stage == .ready)
        #expect(player.blockIndex == 1)
        #expect(player.summary.blocks.map(\.kind.id) == ["hear"])
    }

    @Test func oneThatNeedsSoundResumesOnceItIsBack() {
        var player = playing(kinds: [hear, kind("b")])
        player.handle(.output(works: false, at: s(112)))
        player.handle(.output(works: true, at: s(118)))
        #expect(player.stage == .paused)
        player.handle(.resume(at: s(120)))
        #expect(player.stage == .playing)
        #expect(player.blockIndex == 0)
    }

    @Test func aComingBlockThatNeedsSoundIsLeftOut() {
        var player = playing(kinds: [kind("a"), hear, kind("b")])
        player.handle(.output(works: false, at: s(112)))
        #expect(player.isLeftOut(block: 1))
        #expect(!player.isLeftOut(block: 2))
        #expect(player.timeToFinish == s(170 + 5 + 180))
        player.handle(.resume(at: s(120)))
        player.handle(.next(at: s(121)))
        #expect(player.blockIndex == 2)
        player.handle(.output(works: true, at: s(122)))
        #expect(player.isLeftOut(block: 1))
        player.handle(.end(at: s(123)))
        #expect(player.summary.blocks.map(\.kind.id) == ["a"])
    }

    @Test func withNothingAfterItTheSessionIsOver() {
        var player = playing(kinds: [kind("a"), hear])
        player.handle(.output(works: false, at: s(112)))
        player.handle(.resume(at: s(120)))
        player.handle(.next(at: s(121)))
        #expect(player.stage == .finished)
        #expect(!player.endedEarly)
    }

    @Test func onAReadyCardOnlyABlockThatNeedsSoundPauses() {
        var player = playing(kinds: [kind("a"), hear, kind("b")])
        player.handle(.next(at: s(110)))
        player.handle(.output(works: false, at: s(111)))
        #expect(player.stage == .paused)
        player.handle(.resume(at: s(112)))
        #expect(player.stage == .ready)
        #expect(player.blockIndex == 2)
        player.handle(.output(works: true, at: s(113)))
        player.handle(.output(works: false, at: s(114)))
        #expect(player.stage == .ready)
    }
}
