import Testing
import TheoryCore
import PracticeCore

/// G major in the E shape, on D-G-B, with I–V–vi–IV at 60 BPM: a time through is 16 s after a 4 s count-in.
private let gTheme = Theme(key: .major(.g), position: .init(system: .caged, number: CAGEDShape.e.number), stringSet: .dGB,
                           progression: Progression.named("I–V–vi–IV")!)

private func themed(_ theme: Theme = gTheme, tuning: Tuning = .standard) -> DrillSetup {
    var setup = DrillSetup(fretboard: Fretboard(tuning: tuning), seed: 1)
    setup.follow(theme)
    setup.options.backing = BackingSettings(tempo: 60)
    return setup
}

private func routine(_ setup: DrillSetup = themed(), day: Int = 0, hasSound: Bool = true, unlocked: Bool = false,
                     circleBests: [DrillKind: CircleResult] = [:]) -> SessionRoutine {
    SessionPlanner.routine(for: setup, day: day, hasSound: hasSound, hearFindItUnlocked: unlocked,
                           circleBests: circleBests)
}

private func player(_ routine: SessionRoutine = routine(), hasSound: Bool = true) -> SessionPlayer {
    var player = SessionPlayer(blocks: routine.blocks, setup: themed(), hasSound: hasSound)
    player.handle(.start(at: s(99)))
    return player
}

/// The player's block `step` (from 1) playing from 100 s, every block before it moved on from with Space.
private func playing(step: Int, _ routine: SessionRoutine = routine(), hasSound: Bool = true) -> SessionPlayer {
    var player = player(routine, hasSound: hasSound)
    while player.blockIndex < step - 1, player.stage != .finished {
        player.handle(.next(at: s(99)))
        player.handle(.next(at: s(99)))
    }
    player.handle(.next(at: s(100)))
    return player
}

private let steps: [DrillKind] = [.noteCircle, .notePlayIt, .scaleCircle, .upAndDown, .triadCircle, .chordsInPosition,
                                  .stayInPosition, .freeTime]

@Suite("Daily routine")
struct SessionRoutineTests {
    @Test func theEightStepsInOrder() {
        let routine = routine()
        #expect(routine.blocks.map(\.kind) == steps)
        #expect(routine.blocks.allSatisfy { !$0.isLeftOut })
        #expect(routine.notices.isEmpty)
        #expect(routine.nothingToPromptReason == nil)
    }

    @Test func thePlayerGoesThroughThemInOrder() {
        var player = player()
        var played: [DrillKind] = []
        for _ in steps {
            player.handle(.next(at: s(100)))
            if let kind = player.drill?.kind { played.append(kind) }
            player.handle(.next(at: s(100)))
        }
        #expect(played == steps)
        #expect(player.stage == .finished)
    }

    @Test func stepTwoAlternatesByDay() {
        let kinds = (0..<6).map { routine(day: 739_000 + $0).blocks[1].kind }
        #expect(kinds == [.notePlayIt, .fretNameIt, .notePlayIt, .fretNameIt, .notePlayIt, .fretNameIt])
    }

    @Test func onceUnlockedHearFindItTakesEveryThirdDay() {
        // 739 002 is a multiple of 3.
        let kinds = (739_002..<739_008).map { routine(day: $0, unlocked: true).blocks[1].kind }
        #expect(kinds == [.hearFindIt, .fretNameIt, .notePlayIt, .hearFindIt, .notePlayIt, .fretNameIt])
    }

    @Test func withoutSoundHearFindItsDayKeepsTheAlternation() {
        #expect(routine(day: 739_002, hasSound: false, unlocked: true).blocks[1].kind == .notePlayIt)
        #expect(routine(day: 739_005, hasSound: false, unlocked: true).blocks[1].kind == .fretNameIt)
    }

    @Test func hearFindItUnlocksAfterThreeCompleteNoteCirclesWithNoWrongNotes() {
        func circle(wrong: Int, complete: Bool = true) -> CircleResult {
            CircleResult(time: s(300), wrongNotes: wrong, skips: 0, isComplete: complete)
        }
        let clean = circle(wrong: 0)
        #expect(SessionPlanner.unlocksHearFindIt(noteCircles: [clean, clean, clean]))
        #expect(!SessionPlanner.unlocksHearFindIt(noteCircles: [clean, clean]))
        #expect(!SessionPlanner.unlocksHearFindIt(noteCircles: [clean, clean, circle(wrong: 1)]))
        #expect(SessionPlanner.unlocksHearFindIt(noteCircles: [circle(wrong: 2), clean, clean, clean]))
        // Unfinished circles don't count, either way.
        #expect(SessionPlanner.unlocksHearFindIt(noteCircles: [clean, clean, circle(wrong: 3, complete: false), clean]))
        #expect(!SessionPlanner.unlocksHearFindIt(noteCircles: [clean, clean, circle(wrong: 0, complete: false)]))
    }

    @Test func withoutSoundStepsSixToEightAreLeftOut() {
        let routine = routine(hasSound: false)
        #expect(routine.blocks.map(\.kind) == steps)
        #expect(routine.blocks.map(\.isLeftOut) == [false, false, false, false, false, true, true, true])
        #expect(routine.notices == ["No sound: Chords in position, Stay in position and Free time are left out, and chimes flash."])
        var player = playing(step: 5, routine, hasSound: false)
        #expect(player.drill?.kind == .triadCircle)
        #expect((5...7).allSatisfy { player.isLeftOut(block: $0) })
        player.handle(.next(at: s(110)))
        #expect(player.stage == .finished)
        #expect(!player.endedEarly)
    }

    @Test func withoutSoundOrAProgressionOnlyTheProgressionNoticeNamesThem() {
        var theme = gTheme
        theme.progression = nil
        #expect(routine(themed(theme), hasSound: false).notices == [
            "No sound: chimes flash.",
            "Progressions are left out: no progression in G major has every chord in the E shape.",
        ])
    }

    @Test func withoutAProgressionStepsSixToEightAreLeftOut() {
        var theme = gTheme
        theme.progression = nil
        let routine = routine(themed(theme))
        #expect(routine.blocks.map(\.isLeftOut) == [false, false, false, false, false, true, true, true])
        #expect(routine.notices == ["Progressions are left out: no progression in G major has every chord in the E shape."])
    }

    @Test func plannedLengthsAndExtend() {
        let routine = routine()
        #expect(routine.blocks.map(\.length) == [nil, s(120), nil, s(60), nil, nil, nil, nil])
        var player = playing(step: 2)
        player.handle(.extend(at: s(110)))
        #expect(player.length(ofBlock: 1) == s(240))
        player.handle(.next(at: s(111)))
        player.handle(.next(at: s(112)))
        player.handle(.next(at: s(113)))
        player.handle(.next(at: s(114)))       // step 4 playing
        player.handle(.extend(at: s(115)))
        #expect(player.length(ofBlock: 3) == s(180))
        var circle = playing(step: 1)
        circle.handle(.extend(at: s(110)))
        #expect(circle.length(ofBlock: 0) == nil)
        #expect(circle.timeLeft(inBlock: 0) == nil)
    }

    @Test func aPlannedBlockChimesButGoesOnUntilThePlayerMovesOn() {
        var player = playing(step: 2)
        for second in 101...400 {
            player.handle(.tick(at: s(Double(second))))
            if let name = player.drill?.prompt?.name { player.handle(.played(Pitch(52 + name.pitchClass.value), onset: s(Double(second)), at: s(Double(second)))) }
        }
        #expect(player.blockIndex == 1)
        #expect(player.stage == .playing)
    }

    @Test func aBlockWhoseDrillIsDoneEndsWithAChime() {
        // Chords in position ends after 3 minutes played, after the chord that is up.
        var player = playing(step: 6)
        #expect(player.drill?.kind == .chordsInPosition)
        _ = player.takeChime()
        player.handle(.tick(at: s(281)))
        #expect(player.stage == .playing)
        #expect(player.takeChime() == nil)
        player.handle(.skip(at: s(282)))
        #expect(player.stage == .ready)
        #expect(player.blockIndex == 6)
        #expect(player.takeChime() == .softChime)
        #expect(player.spent(inBlock: 5) == s(182))
    }

    @Test func stayInPositionEndsOnceEveryVoicingHasComeUpAndAfterFourTimesThrough() throws {
        let setup = themed()
        let position = try #require(setup.progressionPosition)
        let voicings = gTheme.progression!.chords(in: gTheme.key).map { setup.fretboard.voicings(of: $0, in: position).count }
        let timesThrough = max(4, voicings.max() ?? 0)
        #expect(routine().blocks[6].end == .afterTimesThrough(timesThrough))
        var player = playing(step: 7)
        #expect(player.drill?.kind == .stayInPosition)
        _ = player.takeBacking()
        _ = player.takeChime()
        // The count-in is 100–104 s; time through n ends at 104 + 16n s.
        let end = 104 + 16 * Double(timesThrough)
        var second = 100.0
        var chime: AppSound?
        while second < end - 1 {
            second += 0.5
            player.handle(.tick(at: s(second)))
            chime = chime ?? player.takeChime()
        }
        #expect(chime == nil)
        #expect(player.blockIndex == 6)
        #expect(player.stage == .playing)
        player.handle(.tick(at: s(end + 0.5)))
        #expect(player.takeChime() == .softChime)
        #expect(player.blockIndex == 7)
        #expect(player.stage == .ready)
    }

    @Test func freeTimeGoesOnUntilTheSessionEndsAndEndingThereCompletesIt() {
        var player = playing(step: 8)
        #expect(player.drill?.kind == .freeTime)
        player.handle(.tick(at: s(2000)))
        #expect(player.stage == .playing)
        player.handle(.end(at: s(2001)))
        #expect(player.stage == .finished)
        #expect(!player.endedEarly)
    }

    @Test func theSessionCanEndAfterAnyBlock() {
        var player = playing(step: 3)
        player.handle(.next(at: s(110)))
        #expect(player.stage == .ready)
        player.handle(.end(at: s(111)))
        #expect(player.stage == .finished)
        #expect(player.endedEarly)
        #expect(player.summary.blocks.map(\.kind) == [.noteCircle, .notePlayIt, .scaleCircle])
    }

    @Test func stepFourIsOnlyTheThemesScaleInItsPosition() throws {
        let player = playing(step: 4)
        let drill = try #require(player.drill)
        #expect(drill.kind == .upAndDown)
        #expect(drill.setup.passPositions.map(\.id) == [gTheme.position])
        #expect(drill.display?.headline == "G major · up and down")
    }

    @Test func circleStepsStartFromTheThemeAgainstTheirBest() throws {
        let best = CircleResult(time: s(400), wrongNotes: 1, skips: 0, isComplete: true)
        let routine = routine(circleBests: [.scaleCircle: best])
        let scales = playing(step: 3, routine)
        #expect(scales.drill?.setup.circleBest == best)
        #expect(scales.drill?.display?.circle?.key == .major(.g))
        let notes = playing(step: 1, routine)
        #expect(notes.drill?.setup.circleBest == nil)
        #expect(notes.drill?.display?.circle?.key == .major(.g))
    }

    @Test func aTriadCircleThatCantGoRoundTheThemesStringSetUsesAnother() throws {
        // E-A-D in Drop D has strings an octave apart.
        var theme = gTheme
        theme.key = .major(.d)
        theme.stringSet = .eAD
        let setup = themed(theme, tuning: TuningPreset.dropD.tuning)
        #expect(DrillKind.triadCircle.makeDrill(setup).nothingToPromptReason != nil)
        let block = routine(setup).blocks[4]
        #expect(!block.isLeftOut)
        #expect(DrillKind.triadCircle.makeDrill(try #require(block.setup)).nothingToPromptReason == nil)
    }

    @Test func aStepWithNothingToPromptIsLeftOutWithANotice() {
        var setup = themed()
        setup.options.frets = 2...2
        setup.options.strings = [5]     // F♯ alone
        let routine = routine(setup, day: 739_001)
        #expect(routine.blocks[1].kind == .fretNameIt)
        #expect(routine.blocks[1].isLeftOut)
        #expect(routine.notices.contains(
            "Fret → name it is left out: No natural notes in these frets and strings. Choose All notes."))
        #expect(!routine.blocks[0].isLeftOut)
        #expect(routine.nothingToPromptReason == nil)
    }
}

@Suite("Session estimate")
struct SessionEstimateTests {
    @Test func theMedianOfPastSessionsOnceThereAreThree() {
        #expect(SessionPlanner.estimate(from: []) == nil)
        #expect(SessionPlanner.estimate(from: [s(600), s(1200)]) == nil)
        #expect(SessionPlanner.estimate(from: [s(1200), s(600), s(2400)]) == s(1200))
        #expect(SessionPlanner.estimate(from: [s(1200), s(600), s(2400), s(1000)]) == s(1100))
    }
}
