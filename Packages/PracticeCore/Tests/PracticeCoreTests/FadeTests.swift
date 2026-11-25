import Testing
import TheoryCore
import PracticeCore

private let eShape = FadeStages.Subject(tuning: .standard, scaleKind: .major, position: .init(system: .caged, number: 1))

/// A pass of three notes, one attempt each.
private func pass(_ subject: FadeStages.Subject = eShape, at stage: FadeStage = .shown, clean: Bool = true,
                  hinted: Bool = false, places: [Int] = [0, 1, 2], last: Attempt.Outcome = .answered) -> [PassNote] {
    places.map { place in
        let outcome: Attempt.Outcome = place == places.last ? last : .answered
        return PassNote(subject: subject, stage: stage, hinted: hinted && place > 0, size: 3, place: place,
                        outcome: outcome, firstRight: outcome == .answered && (clean || place != 1))
    }
}

/// As the log has them, each pass a group.
private func fold(_ passes: [[PassNote]]) -> FadeStages {
    FadeStages(log: passes.enumerated().flatMap { number, notes in notes.map { (group: number, note: $0) } })
}

private func stage(after passes: [PassNote]...) -> FadeStage { fold(passes).stage(of: eShape) }

@Suite("Fade stages from the log")
struct FadeStagesTests {
    @Test func startsShown() {
        #expect(stage() == .shown)
        #expect(FadeStages().stage(of: eShape) == .shown)
    }

    @Test func oneOnForEachCleanPassUpToHidden() {
        #expect(stage(after: pass()) == .faded)
        #expect(stage(after: pass(), pass(at: .faded)) == .hidden)
        #expect(stage(after: pass(), pass(at: .faded), pass(at: .hidden)) == .hidden)
    }

    @Test func oneBackForEachOtherPassDownToShown() {
        #expect(stage(after: pass(clean: false)) == .shown)
        #expect(stage(after: pass(), pass(at: .faded, clean: false)) == .shown)
        #expect(stage(after: pass(), pass(at: .faded), pass(at: .hidden, clean: false)) == .faded)
    }

    @Test func aHintOrATimeoutIsntClean() {
        #expect(stage(after: pass(), pass(at: .faded, hinted: true)) == .shown)
        #expect(stage(after: pass(), pass(at: .faded, last: .timedOut)) == .shown)
    }

    @Test func passesPlayedAtAnotherStageDontCount() {
        #expect(stage(after: pass(at: .hidden)) == .shown)
        #expect(stage(after: pass(), pass(at: .shown, clean: false)) == .faded)
        #expect(stage(after: pass(), pass(at: .hidden, clean: false), pass(at: .faded)) == .hidden)
    }

    @Test func aPassCutShortCountsNeitherWay() {
        #expect(stage(after: pass(), pass(at: .faded, clean: false, places: [0, 1])) == .faded)
        #expect(stage(after: pass(places: [0, 1])) == .shown)
        // A skip cuts it short, on the last note too.
        #expect(stage(after: pass(), pass(at: .faded, last: .skipped)) == .faded)
        // A pass started again is another group: two halves aren't a whole.
        #expect(stage(after: pass(places: [0, 1]), pass(places: [2])) == .shown)
        #expect(stage(after: pass(places: [0, 1, 1])) == .shown)
    }

    @Test func theNotesOfAGroupNeedntBeInOrder() {
        #expect(stage(after: pass(places: [2, 0, 1])) == .faded)
    }

    @Test func keptPerScaleKindPositionAndTuning() {
        var other = eShape
        other.position = .init(system: .caged, number: 2)
        #expect(stage(after: pass(other)) == .shown)
        other = eShape
        other.position = .init(system: .threeNotesPerString, number: 1)
        #expect(stage(after: pass(other)) == .shown)
        other = eShape
        other.scaleKind = .majorPentatonic
        #expect(stage(after: pass(other)) == .shown)
        other = eShape
        other.tuning = TuningPreset.dropD.tuning
        #expect(stage(after: pass(other)) == .shown)
    }

    @Test func theOctaveIsIgnored() {
        var octaveUp = eShape
        octaveUp.position = .init(system: .caged, number: 1, octave: 1)
        #expect(stage(after: pass(octaveUp)) == .faded)
        #expect(fold([pass()]).stage(of: octaveUp) == .faded)
    }
}

// MARK: - In a drill

/// A minor pentatonic at frets 5–8, up, then the whole pass.
private let up = [45, 48, 50, 52, 55, 57, 60, 62, 64, 67, 69, 72]
private let wholePass = up + up.dropLast().reversed()

private let gShape = FadeStages.Subject(tuning: .standard, scaleKind: .minorPentatonic, position: .init(system: .caged, number: 5))

private func setup(_ stages: FadeStages = FadeStages(), key: Key = .minor(.a), capo: Int = 0, octave: Int = 0,
                   override: FadeStage? = nil) -> DrillSetup {
    var options = DrillOptions()
    options.key = key
    options.scaleKind = .minorPentatonic
    options.position = Position.ID(system: .caged, number: CAGEDShape.g.number, octave: octave)
    // The ladder has its own tests.
    options.pass.holdsTempo = true
    options.pass.fadeStage = override
    var setup = DrillSetup(fretboard: Fretboard(tuning: .standard, capo: capo), options: options, seed: 1)
    setup.fadeStages = stages
    return setup
}

/// Running, with beat 1 at 4 s.
private func started(_ setup: DrillSetup) -> any Drill {
    var drill = DrillKind.upAndDown.makeDrill(setup)
    drill.handle(.start(at: s(0)))
    return drill
}

private func started(at stage: FadeStage) -> any Drill { started(setup(reached(stage))) }

private func reached(_ stage: FadeStage) -> FadeStages {
    switch stage {
    case .shown: fold([])
    case .faded: fold([pass(gShape)])
    case .hidden: fold([pass(gShape), pass(gShape, at: .faded)])
    }
}

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

private func isAllFaint(_ drill: any Drill, count: Int) -> Bool {
    drill.display.map { $0.markers.count == count && $0.markers.allSatisfy { $0.isFaint && $0.label.isEmpty } } ?? false
}

private func showsAll(_ drill: any Drill) -> Bool {
    drill.display.map { $0.markers.count == 12 && $0.markers.allSatisfy { !$0.isFaint && !$0.label.isEmpty } } ?? false
}

@Suite("Fading in a drill")
struct PassFadeTests {
    @Test func shownHasDotsAndNames() {
        #expect(showsAll(started(at: .shown)))
    }

    @Test func fadedHasFaintDotsWithoutNames() {
        #expect(isAllFaint(started(at: .faded), count: 12))
    }

    @Test func hiddenHasFaintRootsOnly() {
        let drill = started(at: .hidden)
        #expect(isAllFaint(drill, count: 3))
        #expect(drill.display?.markers.allSatisfy { $0.isAnswer } == true)
    }

    @Test(arguments: [FadeStage.faded, .hidden])
    func onlyTheLastNotePlayedIsLit(_ stage: FadeStage) throws {
        var drill = started(at: stage)
        play(45, at: 4, &drill)
        play(48, at: 5, &drill)
        let markers = try #require(drill.display).markers
        let lit = markers.filter { !$0.isFaint }
        #expect(lit.map(\.location) == [FretboardLocation(string: 0, fret: 8)])
        #expect(lit.map(\.label) == ["C"])
        #expect(lit.allSatisfy { $0.isLastPlayed })
        #expect(markers.count == (stage == .faded ? 12 : 4))
    }

    @Test func theStageReachedCarriesOverToAnyKeyOctaveAndCapo() {
        for setup in [setup(reached(.faded), key: .minor(.d)), setup(reached(.faded), capo: 3),
                      setup(reached(.faded), octave: 1)] {
            #expect(started(setup).display?.markers.allSatisfy { $0.isFaint } == true)
        }
    }

    @Test func eachPassMovesIt() {
        var drill = started(at: .shown)
        playPass(from: 4, &drill)
        #expect(facts(drill)?.fadeStage == .shown)
        // Until the next pass.
        #expect(showsAll(drill))
        drill.handle(.tick(at: s(16.1)))
        #expect(isAllFaint(drill, count: 12))
        playPass(from: 20, &drill)
        #expect(facts(drill)?.fadeStage == .faded)
        #expect(drill.passes.map(\.isClean) == [true, true])
        drill.handle(.tick(at: s(32.1)))
        #expect(isAllFaint(drill, count: 3))
        playPass(from: 36, wrongFirst: true, &drill)
        #expect(facts(drill)?.fadeStage == .hidden)
        drill.handle(.tick(at: s(48.1)))
        #expect(isAllFaint(drill, count: 12))
    }

    @Test func aPassCutShortDoesnt() {
        var drill = started(at: .faded)
        play(46, at: 4, &drill)
        play(45, at: 4.5, &drill)
        drill.handle(.pause(at: s(5)))
        drill.handle(.resume(at: s(6)))
        #expect(isAllFaint(drill, count: 12))
        drill.handle(.repeat(at: s(7)))
        #expect(isAllFaint(drill, count: 12))
        drill.handle(.skip(at: s(8)))
        #expect(isAllFaint(drill, count: 12))
    }

    @Test func anOverrideIsPlayedButDoesntMoveIt() {
        var drill = started(setup(reached(.faded), override: .hidden))
        #expect(isAllFaint(drill, count: 3))
        playPass(from: 4, &drill)
        #expect(facts(drill)?.fadeStage == .hidden)
        drill.handle(.passSettings(PassSettings(), at: s(15.5)))
        drill.handle(.tick(at: s(16.1)))
        #expect(isAllFaint(drill, count: 12))
    }

    @Test func theLogOfADrillGivesTheStageItReached() {
        var drill = started(at: .shown)
        playPass(from: 4, &drill)
        let notes = drill.attemptsToLog.compactMap { attempt in
            PassNote(attempt, in: drill.fretboard.tuning).map { (group: attempt.group?.number, note: $0) }
        }
        #expect(notes.count == 23)
        #expect(FadeStages(log: notes).stage(of: gShape) == .faded)
    }

    @Test func theBlocksOfASessionCarryItOn() {
        let block = SessionBlock(kind: .upAndDown, length: s(180))
        var player = SessionPlayer(blocks: [block, block], setup: setup())
        player.handle(.start(at: s(0)))
        player.handle(.next(at: s(0)))
        for (index, midi) in wholePass.enumerated() {
            player.handle(.played(Pitch(midi), onset: s(4 + Double(index)), at: s(4 + Double(index))))
        }
        player.handle(.next(at: s(27)))
        player.handle(.next(at: s(28)))
        #expect(player.display?.markers.allSatisfy { $0.isFaint } == true)
        player.handle(.hint(isShown: true, at: s(29)))
        #expect(player.display?.markers.contains { $0.isFaint } == false)
    }
}

@Suite("Hints")
struct HintTests {
    @Test func showsThePositionUntilReleased() {
        var drill = started(at: .hidden)
        drill.handle(.hint(isShown: true, at: s(4.1)))
        #expect(showsAll(drill))
        drill.handle(.hint(isShown: false, at: s(4.2)))
        #expect(isAllFaint(drill, count: 3))
    }

    @Test func thatPassIsHintedAndNotClean() {
        var drill = started(at: .hidden)
        drill.handle(.hint(isShown: true, at: s(4.01)))
        drill.handle(.hint(isShown: false, at: s(4.02)))
        playPass(from: 4, &drill)
        #expect(facts(drill)?.hinted == true)
        #expect(drill.passes.map(\.isClean) == [false])
        #expect(drill.display?.feedback == "Pass done · hint used")
        drill.handle(.tick(at: s(16.1)))
        #expect(isAllFaint(drill, count: 12))
        playPass(from: 20, &drill)
        #expect(facts(drill)?.hinted == false)
        #expect(drill.passes.map(\.isClean) == [false, true])
    }

    @Test func inTheCountInToo() {
        var drill = started(at: .hidden)
        drill.handle(.hint(isShown: true, at: s(1)))
        drill.handle(.hint(isShown: false, at: s(2)))
        playPass(from: 4, &drill)
        #expect(facts(drill)?.hinted == true)
    }

    @Test func afterAPassItDoesntCountUnlessHeldIntoTheNext() {
        var drill = started(at: .hidden)
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
        var drill = started(at: .hidden)
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
        var drill = started(at: .hidden)
        drill.handle(.hint(isShown: true, at: s(4.1)))
        drill.handle(.pause(at: s(5)))
        drill.handle(.hint(isShown: true, at: s(5.5)))
        drill.handle(.resume(at: s(6)))
        #expect(isAllFaint(drill, count: 3))
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
