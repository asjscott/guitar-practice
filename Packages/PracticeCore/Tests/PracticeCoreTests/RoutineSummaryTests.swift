import Testing
import TheoryCore
import PracticeCore

private func subject(_ shape: CAGEDShape, _ kind: Scale.Kind = .major, tuning: Tuning = .standard) -> FadeLevels.Subject {
    FadeLevels.Subject(tuning: tuning, scaleKind: kind, position: Position.ID(system: .caged, number: shape.number))
}

private func shape(_ inversion: Triad.Inversion, _ quality: Triad.Quality = .major, on set: StringSet = .dGB)
    -> FadeLevels.VoicingShape {
    FadeLevels.VoicingShape(tuning: .standard, quality: quality, inversion: inversion, stringSet: set)
}

extension FadeLevels {
    /// Clean or not, a one-note pass of `subject` at the level it has reached.
    fileprivate mutating func pass(_ subject: Subject, isClean: Bool = true) {
        add([Note(subject: subject, level: level(of: subject), hinted: false, size: 1, place: 0,
                  outcome: isClean ? .answered : .timedOut, firstRight: isClean)])
    }

    /// Clean or not, a voicing of `shape` at the level it has reached.
    fileprivate mutating func voicing(_ shape: VoicingShape, isClean: Bool = true) {
        add(voicing: (0..<3).map {
            VoicingNote(shape: shape, level: level(of: shape), hinted: false, place: $0, outcome: .answered,
                        firstRight: isClean)
        })
    }
}

@Suite("Routine summary: fade levels that moved")
struct FadeMoveTests {
    @Test func eachSubjectThatMovedFromBeforeToAfter() {
        var before = FadeLevels()
        before.pass(subject(.a))
        before.pass(subject(.e))
        before.voicing(shape(.second))
        var after = before
        after.pass(subject(.a))
        after.pass(subject(.a))
        after.pass(subject(.g, .minorPentatonic))
        after.voicing(shape(.root))
        after.voicing(shape(.second), isClean: false)
        #expect(after.moves(since: before).map(\.text) == [
            "A shape, major: 1 → 3", "G shape, minor pentatonic: 0 → 1",
            "Root position on D-G-B, major: 0 → 1", "2nd inversion on D-G-B, major: 1 → 0",
        ])
    }

    @Test func nothingMovedIsNoMoves() {
        var levels = FadeLevels()
        levels.pass(subject(.c))
        levels.voicing(shape(.first))
        #expect(levels.moves(since: levels).isEmpty)
        #expect(FadeLevels().moves(since: FadeLevels()).isEmpty)
    }

    @Test func aMoveThereAndBackIsNone() {
        var after = FadeLevels()
        after.pass(subject(.d))
        after.pass(subject(.d), isClean: false)
        #expect(after.moves(since: FadeLevels()).isEmpty)
    }

    @Test func positionsInOrderUpTheShapesThenScaleKindsAndVoicingsBySetThenQualityAndInversion() {
        var after = FadeLevels()
        for subject in [subject(.g), subject(.e, .naturalMinor), subject(.e)] { after.pass(subject) }
        for shape in [shape(.root, .minor), shape(.first, on: .aDG), shape(.second), shape(.root)] { after.voicing(shape) }
        #expect(after.moves(since: FadeLevels()).map(\.text) == [
            "E shape, major: 0 → 1", "E shape, natural minor: 0 → 1", "G shape, major: 0 → 1",
            "1st inversion on A-D-G, major: 0 → 1", "Root position on D-G-B, major: 0 → 1",
            "2nd inversion on D-G-B, major: 0 → 1", "Root position on D-G-B, minor: 0 → 1",
        ])
    }

    @Test func positionsAreNamedForTheirTuning() {
        let dadgad = TuningPreset.dadgad.tuning
        var after = FadeLevels()
        after.pass(subject(.a, tuning: dadgad))
        let move = try? #require(after.moves(since: FadeLevels()).first)
        #expect(move?.text == "Position 4, major: 0 → 1")
        #expect(move?.from == .first)
        #expect(move?.to == FadeLevel(1))
    }
}

private func circle(_ seconds: Double, wrong: Int = 0, skips: Int = 0, complete: Bool = true) -> CircleResult {
    CircleResult(time: s(seconds), wrongNotes: wrong, skips: skips, isComplete: complete)
}

@Suite("Routine summary: circles against the best")
struct CircleTextTests {
    @Test func timeAndWrongNotesAndAnySkipped() {
        #expect(circle(552, wrong: 1).summaryText == "9:12 · 1 wrong")
        #expect(circle(42, skips: 2).summaryText == "0:42 · 0 wrong · 2 skipped")
        #expect(circle(3725).summaryText == "1:02:05 · 0 wrong")
    }

    @Test func againstTheBest() {
        #expect(circle(552).comparison(with: circle(598)) == "New best: −46 s")
        #expect(circle(552).comparison(with: nil) == "First clean circle")
        #expect(circle(600).comparison(with: circle(598)) == "Best 9:58")
        #expect(circle(300, complete: false).comparison(with: circle(598)) == "Not finished")
        #expect(circle(300, skips: 2).comparison(with: circle(598)) == "Not clean: 2 skipped")
        #expect(circle(300, wrong: 1).comparison(with: circle(598)) == "Not clean: 1 wrong")
        #expect(circle(300, wrong: 2, skips: 1).comparison(with: circle(598)) == "Not clean: 2 wrong · 1 skipped")
    }
}

/// E major's C shape round the circle, each note of pass n played `seconds[n]` after its prompt.
private func scaleCircle(_ seconds: [Double]) -> [Attempt] {
    var setup = DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1)
    setup.options.key = .major(.e)
    setup.options.position = Position.ID(system: .caged, number: CAGEDShape.c.number)
    var drill = DrillKind.scaleCircle.makeDrill(setup)
    drill.handle(.start(at: s(0)))
    for (pass, interval) in seconds.enumerated() {
        while drill.isRunning, drill.prompt?.pass == pass, let target = drill.prompt?.target, let start = drill.promptStart {
            drill.handle(.played(drill.fretboard.pitch(at: target), onset: start + s(interval), at: start + s(interval)))
            drill.handle(.tick(at: start + s(interval + 0.1)))
        }
    }
    return drill.attempts
}

@Suite("Routine summary: the Scale circle per key")
struct ScaleCircleKeyTimeTests {
    @Test func eachKeysPassTimeInTheOrderPlayed() {
        let attempts = scaleCircle([1, 2, 0.5])
        let notes = (0..<3).map { pass in Double(attempts.filter { $0.group?.number == pass }.count) }
        let times = CircleKeyTime.times(in: attempts)
        #expect(times.map(\.key.shortName) == ["E", "B", "F♯"])
        #expect(times.map(\.time) == [s(notes[0]), s(2 * notes[1]), s(0.5 * notes[2])])
    }

    @Test func noneBeforeAnyIsPlayed() {
        #expect(CircleKeyTime.times(in: []).isEmpty)
    }
}

/// G major in the E shape, on D-G-B, with I–V–vi–IV at 60 BPM.
private func themed() -> DrillSetup {
    var setup = DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1)
    setup.follow(Theme(key: .major(.g), position: .init(system: .caged, number: CAGEDShape.e.number), stringSet: .dGB,
                       progression: Progression.named("I–V–vi–IV")!))
    setup.options.backing = BackingSettings(tempo: 60)
    return setup
}

/// The day's routine, started at 99 s, from fade levels `before`.
private func routine(hasSound: Bool = true, bests: [DrillKind: CircleResult] = [:],
                     before: FadeLevels = FadeLevels()) -> SessionPlayer {
    var setup = themed()
    setup.fadeLevels = before
    let routine = SessionPlanner.routine(for: setup, day: 0, hasSound: hasSound, hearFindItUnlocked: false,
                                         circleBests: bests)
    var player = SessionPlayer(blocks: routine.blocks, setup: setup, hasSound: hasSound)
    player.handle(.start(at: s(99)))
    return player
}

extension SessionPlayer {
    /// Moves on with Space until block `step` (from 1) is playing.
    fileprivate mutating func play(step: Int) {
        while blockIndex < step - 1 || stage != .playing, stage != .finished {
            handle(.next(at: s(99)))
        }
    }

    /// Plays each prompt's pitch a second after its timer starts, then ticks past any pause, `count` times or until
    /// the block is over.
    fileprivate mutating func playRight(_ count: Int = 1000, after seconds: Double = 1) {
        let block = blockIndex
        for _ in 0..<count {
            guard stage == .playing, blockIndex == block, let drill, let target = drill.prompt?.target,
                  let start = drill.promptStart else { return }
            handle(.played(drill.fretboard.pitch(at: target), onset: start + s(seconds), at: start + s(seconds)))
            handle(.tick(at: start + s(seconds + 0.6)))
        }
    }
}

@Suite("Routine summary: from the session")
struct RoutineSummaryFromSessionTests {
    @Test func aCircleAgainstTheBestBeforeTheSession() throws {
        let best = circle(600)
        var player = routine(bests: [.noteCircle: best])
        player.play(step: 1)
        player.playRight()
        // Past the circle's end, which is held to be read: the block is over.
        player.handle(.tick(at: s(990)))
        #expect(player.blockIndex == 1)
        player.handle(.end(at: s(1000)))
        let summary = player.summary
        let block = try #require(summary.blocks.first)
        #expect(block.step == 0)
        #expect(block.circleBest == best)
        // Frets 0–12 on six strings, a second each.
        #expect(block.circle == circle(78))
        #expect(block.resultText == "1:18 · 0 wrong")
        #expect(summary.circles.map(\.kind) == [.noteCircle])
    }

    @Test func theSlowestPromptsLeaveOutTheScaleCircle() {
        var player = routine()
        player.play(step: 1)
        player.playRight(3, after: 2)
        player.play(step: 3)
        player.playRight(3, after: 5)
        player.handle(.end(at: s(1000)))
        let slowest = player.summary.slowest(3)
        #expect(slowest.count == 3)
        #expect(slowest.allSatisfy { $0.responseTime == s(2) })
    }

    @Test func aCircleNotFinishedSaysSo() {
        var player = routine()
        player.play(step: 1)
        player.playRight(3)
        player.handle(.end(at: s(1000)))
        #expect(player.summary.blocks.first?.resultText == "0:03 · 0 wrong · not finished")
    }

    @Test func theScaleCircleKeysInTheOrderPlayed() {
        var player = routine()
        player.play(step: 3)
        for _ in 0..<3 {
            let pass = player.drill?.prompt?.pass
            while player.stage == .playing, player.drill?.prompt?.pass == pass { player.playRight(1) }
        }
        let keys = player.summary.scaleCircleKeys
        #expect(keys.map(\.key.shortName) == ["G", "D", "A"])
        #expect(keys.allSatisfy { $0.time > .zero })
    }

    @Test func theFadeLevelsThatMovedFromBeforeTheSession() {
        var before = FadeLevels()
        before.pass(subject(.e))
        var after = before
        after.pass(subject(.e))
        after.voicing(shape(.root))
        var player = routine(before: before)
        player.play(step: 3)
        player.handle(.fadeLevels(after))
        player.handle(.end(at: s(1000)))
        #expect(player.summary.fadeMoves.map(\.text) == ["E shape, major: 1 → 2", "Root position on D-G-B, major: 0 → 1"])
    }

    @Test func triadVoicingsMoveToo() {
        var player = routine()
        player.play(step: 5)
        player.playRight(6)
        // Through the steps after it.
        while player.stage != .finished { player.handle(.next(at: s(1000))) }
        #expect(player.summary.fadeMoves.map(\.text)
                == ["Root position on D-G-B, major: 0 → 1", "2nd inversion on D-G-B, major: 0 → 1"])
    }

    @Test func promptsRightFirstTimeAndTheirMedianTime() {
        var player = SessionPlayer(blocks: [SessionBlock(kind: kind("a"), length: s(180))],
                                   setup: DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1))
        player.handle(.start(at: s(100)))
        player.handle(.next(at: s(102)))
        // E after a wrong note in 3 s, F in 1 s, F♯ skipped.
        player.handle(.typed(.g, at: s(103)))
        player.handle(.typed(.e, at: s(105.6)))
        player.handle(.tick(at: s(106)))
        player.handle(.typed(.f, at: s(107.6)))
        player.handle(.tick(at: s(108)))
        player.handle(.skip(at: s(109)))
        player.handle(.end(at: s(110)))
        #expect(player.summary.blocks.first?.resultText == "1 of 2 right · 2.0 s each")
    }

    @Test func everyStepPlayed() {
        var player = routine()
        while player.stage != .finished { player.handle(.next(at: s(100))) }
        let summary = player.summary
        #expect(!summary.endedEarly)
        #expect(summary.blocks.map(\.step) == Array(0..<8))
        #expect(summary.headline == "1 minute, every step")
    }

    @Test func stepsLeftOut() {
        var player = routine(hasSound: false)
        while player.stage != .finished { player.handle(.next(at: s(100))) }
        #expect(player.summary.headline == "1 minute, 5 of 8 steps")
    }

    @Test func endingInFreeTimeIsNotEarly() {
        var player = routine()
        player.play(step: 8)
        player.handle(.tick(at: s(608.4)))
        player.handle(.end(at: s(608.5)))
        let summary = player.summary
        #expect(!summary.endedEarly)
        #expect(summary.blocks.last?.resultText == "8:29")
        #expect(summary.headline == "8 minutes, every step")
    }

    @Test func endedEarly() {
        var player = routine()
        player.play(step: 2)
        player.handle(.end(at: s(250)))
        let summary = player.summary
        #expect(summary.endedEarly)
        #expect(summary.blocks.map(\.kind) == [.noteCircle, .notePlayIt])
        #expect(summary.headline == "3 minutes, ended early")
    }
}
