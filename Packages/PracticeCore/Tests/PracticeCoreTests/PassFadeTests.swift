import Testing
import TheoryCore
import PracticeCore

/// A minor pentatonic at frets 5–8, up, then the whole pass: 23 notes, so at 60 BPM an expected time of 23 s.
private let up = [45, 48, 50, 52, 55, 57, 60, 62, 64, 67, 69, 72]
private let wholePass = up + up.dropLast().reversed()

private let gShape = FadeLevels.Subject(tuning: .standard, scaleKind: .minorPentatonic, position: .init(system: .caged, number: 5))

/// Clean passes from level 0 up to `level`, as the log has them.
private func reached(_ level: Int) -> FadeLevels {
    FadeLevels(log: (0..<level).flatMap { number in
        (0..<3).map { place in
            (group: number, note: FadeLevels.Note(subject: gShape, level: FadeLevel(number), hinted: false, size: 3,
                                                  place: place, outcome: .answered, firstRight: true))
        }
    })
}

private func setup(_ levels: FadeLevels = FadeLevels(), key: Key = .minor(.a), capo: Int = 0, octave: Int = 0,
                   override: Int? = nil) -> DrillSetup {
    var options = DrillOptions()
    options.key = key
    options.scaleKind = .minorPentatonic
    options.position = Position.ID(system: .caged, number: CAGEDShape.g.number, octave: octave)
    // The ladder has its own tests.
    options.pass.holdsTempo = true
    options.pass.fadeLevel = override.map(FadeLevel.init)
    var setup = DrillSetup(fretboard: Fretboard(tuning: .standard, capo: capo), options: options, seed: 1)
    setup.fadeLevels = levels
    return setup
}

/// Running, with beat 1 at 4 s.
private func started(_ setup: DrillSetup) -> any Drill {
    var drill = DrillKind.upAndDown.makeDrill(setup)
    drill.handle(.start(at: s(0)))
    return drill
}

private func started(at level: Int) -> any Drill { started(setup(reached(level))) }

private func play(_ midi: Int, at time: Double, _ drill: inout any Drill) {
    drill.handle(.played(Pitch(midi), onset: s(time), at: s(time)))
}

/// Two notes a second, so over 11 s after `start`.
private func playPass(from start: Double, wrongFirst: Bool = false, _ drill: inout any Drill) {
    if wrongFirst { play(47, at: start, &drill) }
    for (index, midi) in wholePass.enumerated() { play(midi, at: start + 0.1 + Double(index) * 0.5, &drill) }
}

/// The last note's.
private func facts(_ drill: any Drill) -> PassFacts? {
    if case .pass(let facts) = drill.attempts.last?.facts { facts } else { nil }
}

/// The markers at `time`.
private func markers(_ drill: inout any Drill, at time: Double) -> [DrillDisplay.Marker] {
    drill.handle(.tick(at: s(time)))
    return drill.display?.markers ?? []
}

private func showsAll(_ markers: [DrillDisplay.Marker]) -> Bool {
    markers.count == 12 && markers.allSatisfy { $0.opacity == 1 && !$0.label.isEmpty }
}

private func showsAll(_ drill: any Drill) -> Bool { showsAll(drill.display?.markers ?? []) }

/// The position's three A's, solid.
private func rootsOnly(_ markers: [DrillDisplay.Marker]) -> Bool {
    markers.count == 3 && markers.allSatisfy { $0.isAnswer && $0.opacity == 1 && $0.label == "A" }
}

private func rootsOnly(_ drill: any Drill) -> Bool { rootsOnly(drill.display?.markers ?? []) }

/// Of the roots or the other notes, to three places.
private func opacities(_ markers: [DrillDisplay.Marker], roots: Bool) -> Set<Double> {
    Set(markers.filter { $0.isAnswer == roots }.map { ($0.opacity * 1000).rounded() / 1000 })
}

@Suite("Fading in a drill")
struct PassFadeTests {
    @Test func aNewSubjectIsShownTheWholePass() {
        var drill = started(at: 0)
        for time in [2.0, 4, 20, 40] { #expect(showsAll(markers(&drill, at: time))) }
    }

    /// Level 1 fades by 90 % of 23 s: 20.7 s from beat 1.
    @Test func eachNoteFadesLinearlyByTheFadeTime() {
        var drill = started(at: 1)
        #expect(showsAll(markers(&drill, at: 2)))
        #expect(showsAll(markers(&drill, at: 4)))
        // Slowly, within each note's time limit. The notes played stay solid.
        for (midi, time) in [(45, 4.0), (48, 8), (50, 12), (52, 14)] { play(midi, at: time, &drill) }
        let halfway = markers(&drill, at: 4 + 10.35)
        #expect(halfway.count == 12)
        #expect(opacities(halfway, roots: false) == [1, 0.5])
        #expect(opacities(halfway, roots: true) == [1])
        play(55, at: 18, &drill)
        #expect(opacities(markers(&drill, at: 4 + 15.525), roots: false) == [1, 0.25])
        play(57, at: 23, &drill)
        let gone = markers(&drill, at: 4 + 20.7)
        #expect(gone.count == 3 + 4)
        #expect(gone.allSatisfy { $0.opacity == 1 })
    }

    @Test func theFadeTimeFollowsTheTempo() {
        var settings = setup(reached(1))
        settings.options.pass.tempo = 120
        var drill = started(settings)
        // 23 clicks of 0.5 s, from beat 1 at 2 s: gone by 10.35 s after it, so 2 s in, 1 − 2 / 10.35 is left.
        #expect(opacities(markers(&drill, at: 2 + 2), roots: false) == [0.807])
    }

    @Test func theLastLevelShowsOnlyTheRootsFromTheStart() {
        var drill = started(at: 6)
        #expect(rootsOnly(markers(&drill, at: 1)))
        #expect(rootsOnly(markers(&drill, at: 4)))
    }

    @Test(arguments: [1, 6])
    func notesPlayedStaySolidAndTheLastIsRinged(_ level: Int) {
        var drill = started(at: level)
        play(45, at: 4, &drill)
        play(48, at: 5, &drill)
        let now = markers(&drill, at: 8)
        let c = FretboardLocation(string: 0, fret: 8)
        #expect(now.count == (level == 6 ? 4 : 12))
        #expect(now.filter { $0.opacity == 1 }.count == 4)
        #expect(now.filter(\.isLastPlayed).map(\.location) == [c])
        #expect(now.first { $0.location == c }.map { "\($0.label) \($0.opacity)" } == "C 1.0")
    }

    /// 4 s into level 1's 20.7 s, 1 − 4 / 20.7 is left.
    @Test func theLevelReachedCarriesOverToAnyKeyOctaveAndCapo() {
        for setup in [setup(reached(1), key: .minor(.d)), setup(reached(1), capo: 3), setup(reached(1), octave: 1)] {
            var drill = started(setup)
            #expect(opacities(markers(&drill, at: 8), roots: false) == [0.807])
        }
    }

    @Test func aRunPlaysAtTheLevelReachedBeforeItAndMovesItOneLevelAtMost() {
        var drill = started(at: 2)
        playPass(from: 4, &drill)
        drill.handle(.tick(at: s(16.1)))
        playPass(from: 20, &drill)
        #expect(facts(drill)?.fadeLevel == FadeLevel(2))
        #expect(drill.passes.map(\.isClean) == [true, true])
        // Every pass clean so far: one up, however many.
        #expect(drill.fadeLevels?.level(of: gShape) == FadeLevel(2))
        #expect(drill.fadeLevels?.levelAfterRun(of: gShape) == FadeLevel(3))
        drill.handle(.tick(at: s(32.1)))
        playPass(from: 36, wrongFirst: true, &drill)
        drill.handle(.tick(at: s(48.1)))
        playPass(from: 52, &drill)
        #expect(facts(drill)?.fadeLevel == FadeLevel(2))
        // One not clean: one down, whatever the others.
        #expect(drill.fadeLevels?.levelAfterRun(of: gShape) == FadeLevel(1))
    }

    @Test func theNextRunMovesItAgain() {
        var drill = started(at: 2)
        playPass(from: 4, &drill)
        var levels = drill.fadeLevels ?? FadeLevels()
        levels.endRun()
        var next = started(setup(levels))
        playPass(from: 4, &next)
        #expect(facts(next)?.fadeLevel == FadeLevel(3))
        #expect(next.fadeLevels?.levelAfterRun(of: gShape) == FadeLevel(4))
    }

    @Test func aPassCutShortDoesnt() {
        var drill = started(at: 1)
        play(46, at: 4, &drill)
        play(45, at: 4.5, &drill)
        drill.handle(.pause(at: s(5)))
        drill.handle(.resume(at: s(6)))
        drill.handle(.repeat(at: s(7)))
        drill.handle(.skip(at: s(8)))
        play(45, at: 12, &drill)
        #expect(facts(drill)?.fadeLevel == FadeLevel(1))
    }

    @Test func anOverrideIsPlayedButDoesntMoveIt() {
        var drill = started(setup(reached(1), override: 6))
        #expect(rootsOnly(drill))
        playPass(from: 4, &drill)
        #expect(facts(drill)?.fadeLevel == FadeLevel(6))
        drill.handle(.passSettings(PassSettings(), at: s(15.5)))
        drill.handle(.tick(at: s(16.1)))
        playPass(from: 20, &drill)
        #expect(facts(drill)?.fadeLevel == FadeLevel(1))
    }

    @Test func theLogOfADrillGivesTheLevelItReached() {
        var drill = started(at: 0)
        playPass(from: 4, &drill)
        let notes = drill.attemptsToLog.compactMap { attempt in
            FadeLevels.Note(attempt, in: drill.fretboard.tuning).map { (group: attempt.group?.number, note: $0) }
        }
        #expect(notes.count == 23)
        #expect(FadeLevels(log: notes).level(of: gShape) == FadeLevel(1))
    }

    /// Two blocks of Up and down from level 5: a clean pass in the first, then the second's first pass from 32 s.
    private func sessionOfTwoBlocks() -> SessionPlayer {
        let block = SessionBlock(kind: .upAndDown, length: s(180))
        var player = SessionPlayer(blocks: [block, block], setup: setup(reached(5)))
        player.handle(.start(at: s(0)))
        player.handle(.next(at: s(0)))
        for (index, midi) in wholePass.enumerated() {
            player.handle(.played(Pitch(midi), onset: s(4 + Double(index)), at: s(4 + Double(index))))
        }
        player.handle(.next(at: s(27)))
        player.handle(.next(at: s(28)))
        return player
    }

    @Test func theBlocksOfASessionPlayAtTheLevelFromBeforeIt() {
        var player = sessionOfTwoBlocks()
        #expect(!rootsOnly(player.display?.markers ?? []))
        #expect(player.drill?.fadeLevels?.level(of: gShape) == FadeLevel(5))
        player.handle(.hint(isShown: true, at: s(29)))
        #expect(showsAll(player.display?.markers ?? []))
    }

    @Test func aSessionMovesItOneLevelAtMost() {
        var clean = sessionOfTwoBlocks()
        for (index, midi) in wholePass.enumerated() {
            clean.handle(.played(Pitch(midi), onset: s(32 + Double(index)), at: s(32 + Double(index))))
        }
        clean.handle(.end(at: s(60)))
        #expect(clean.summary.fadeMoves.map(\.text) == ["G shape, minor pentatonic: 5 → 6"])

        var notClean = sessionOfTwoBlocks()
        notClean.handle(.played(Pitch(47), onset: s(32), at: s(32)))
        for (index, midi) in wholePass.enumerated() {
            notClean.handle(.played(Pitch(midi), onset: s(32.5 + Double(index)), at: s(32.5 + Double(index))))
        }
        notClean.handle(.end(at: s(60)))
        #expect(notClean.summary.fadeMoves.map(\.text) == ["G shape, minor pentatonic: 5 → 4"])
    }
}

@Suite("Fading read again from the log")
struct FadeReadAgainTests {
    @Test func resumingFollowsWhatWasReachedMeanwhile() {
        var drill = started(at: 0)
        play(46, at: 4, &drill)
        drill.handle(.pause(at: s(5)))
        drill.handle(.fadeLevels(reached(6)))
        drill.handle(.resume(at: s(6)))
        #expect(rootsOnly(drill))
    }

    @Test func anOverrideIsKept() {
        var drill = started(setup(reached(0), override: 6))
        drill.handle(.pause(at: s(1)))
        drill.handle(.fadeLevels(reached(0)))
        drill.handle(.resume(at: s(2)))
        #expect(rootsOnly(drill))
    }

    private func session(from level: Int = 0) -> SessionPlayer {
        let block = SessionBlock(kind: .upAndDown, length: s(180))
        var player = SessionPlayer(blocks: [block, block], setup: setup(reached(level)))
        player.handle(.start(at: s(0)))
        player.handle(.next(at: s(0)))
        for (index, midi) in wholePass.enumerated() {
            player.handle(.played(Pitch(midi), onset: s(4 + Double(index)), at: s(4 + Double(index))))
        }
        player.handle(.pause(at: s(27)))
        return player
    }

    private func markerCount(_ player: SessionPlayer) -> Int? { player.display?.markers.count }

    @Test func inASession() {
        var player = session()
        player.handle(.fadeLevels(reached(6)))
        player.handle(.resume(at: s(28)))
        #expect(markerCount(player) == 3)
    }

    /// What is read counts the session's own pass, which took it from 5 to the last; another took it back.
    @Test func aSessionsPassesArentCountedTwice() {
        var player = session(from: 5)
        player.handle(.fadeLevels(reached(5)))
        player.handle(.resume(at: s(28)))
        #expect(markerCount(player) == 12)
        player.handle(.next(at: s(29)))
        player.handle(.next(at: s(30)))
        #expect(markerCount(player) == 12)
    }

    @Test func onAReadyCard() {
        let block = SessionBlock(kind: .upAndDown, length: s(180))
        var player = SessionPlayer(blocks: [block], setup: setup())
        player.handle(.start(at: s(0)))
        player.handle(.pause(at: s(1)))
        player.handle(.fadeLevels(reached(6)))
        player.handle(.resume(at: s(2)))
        player.handle(.next(at: s(3)))
        #expect(markerCount(player) == 3)
    }
}

@Suite("Hints")
struct HintTests {
    @Test func showsThePositionUntilReleased() {
        var drill = started(at: 6)
        drill.handle(.hint(isShown: true, at: s(4.1)))
        #expect(showsAll(drill))
        drill.handle(.hint(isShown: false, at: s(4.2)))
        #expect(rootsOnly(drill))
    }

    @Test func thatPassIsHintedAndNotClean() {
        var drill = started(at: 6)
        drill.handle(.hint(isShown: true, at: s(4.01)))
        drill.handle(.hint(isShown: false, at: s(4.02)))
        playPass(from: 4, &drill)
        #expect(facts(drill)?.hinted == true)
        #expect(drill.passes.map(\.isClean) == [false])
        #expect(drill.display?.feedback == "Pass done · hint used")
        drill.handle(.tick(at: s(16.1)))
        playPass(from: 20, &drill)
        #expect(facts(drill)?.fadeLevel == FadeLevel(6))
        #expect(facts(drill)?.hinted == false)
        #expect(drill.passes.map(\.isClean) == [false, true])
        #expect(drill.fadeLevels?.levelAfterRun(of: gShape) == FadeLevel(5))
    }

    @Test func inTheCountInToo() {
        var drill = started(at: 6)
        drill.handle(.hint(isShown: true, at: s(1)))
        drill.handle(.hint(isShown: false, at: s(2)))
        playPass(from: 4, &drill)
        #expect(facts(drill)?.hinted == true)
    }

    @Test func afterAPassItDoesntCountUnlessHeldIntoTheNext() {
        var drill = started(at: 6)
        playPass(from: 4, &drill)
        drill.handle(.hint(isShown: true, at: s(15.5)))
        #expect(showsAll(drill))
        #expect(drill.passes.map(\.isClean) == [true])
        drill.handle(.tick(at: s(16.1)))
        #expect(showsAll(drill))
        drill.handle(.hint(isShown: false, at: s(17)))
        playPass(from: 20, &drill)
        #expect(drill.passes.map(\.isClean) == [true, false])
    }

    @Test func aRestartDropsItUnlessStillHeld() {
        var drill = started(at: 6)
        drill.handle(.hint(isShown: true, at: s(1)))
        drill.handle(.hint(isShown: false, at: s(2)))
        drill.handle(.repeat(at: s(3)))
        play(45, at: 7, &drill)
        #expect(facts(drill)?.hinted == false)
        drill.handle(.hint(isShown: true, at: s(7.5)))
        drill.handle(.repeat(at: s(8)))
        #expect(showsAll(drill))
        play(45, at: 12, &drill)
        #expect(facts(drill)?.hinted == true)
    }

    @Test func pausingEndsIt() {
        var drill = started(at: 6)
        drill.handle(.hint(isShown: true, at: s(4.1)))
        drill.handle(.pause(at: s(5)))
        drill.handle(.hint(isShown: true, at: s(5.5)))
        drill.handle(.resume(at: s(6)))
        #expect(rootsOnly(drill))
        // The key going up then changes nothing.
        drill.handle(.hint(isShown: false, at: s(7)))
        playPass(from: 10, &drill)
        #expect(facts(drill)?.hinted == false)
    }

    @Test func otherDrillsIgnoreIt() {
        var drill = DrillKind.notePlayIt.makeDrill(DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1))
        drill.handle(.start(at: s(0)))
        let before = drill.display
        drill.handle(.hint(isShown: true, at: s(1)))
        #expect(drill.display == before)
    }
}
