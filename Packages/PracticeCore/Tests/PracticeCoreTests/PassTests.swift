import Testing
import TheoryCore
import PracticeCore

/// A minor pentatonic at frets 5–8, up.
private let up = [45, 48, 50, 52, 55, 57, 60, 62, 64, 67, 69, 72]
/// The whole pass: 23 notes.
private let pass = up + up.dropLast().reversed()

private func setup(_ preset: TuningPreset = .standard, capo: Int = 0, change: (inout DrillOptions) -> Void = { _ in }) -> DrillSetup {
    var options = DrillOptions()
    options.key = .minor(.a)
    options.scaleKind = .minorPentatonic
    options.position = Position.ID(system: .caged, number: CAGEDShape.g.number)
    // The ladder has its own tests.
    options.pass.holdsTempo = true
    change(&options)
    return DrillSetup(fretboard: Fretboard(tuning: preset.tuning, capo: capo), options: options, seed: 1)
}

/// Running, with its clicks heard as asked: click 0 at 0 s, and in 4/4 at 60 BPM beat 1 at 4 s.
private func started(_ change: (inout DrillOptions) -> Void = { _ in }) -> any Drill {
    var drill = DrillKind.upAndDown.makeDrill(setup(change: change))
    drill.handle(.start(at: s(0)))
    return drill
}

/// Plays a pitch, heard 0.13 s after its onset.
private func play(_ midi: Int, at time: Double, _ drill: inout any Drill) {
    drill.handle(.played(Pitch(midi), onset: s(time), at: s(time + 0.13)))
}

/// Plays the pass a note per second, the first at `start`.
private func playPass(from start: Double, _ drill: inout any Drill) {
    for (index, midi) in pass.enumerated() { play(midi, at: start + Double(index), &drill) }
}

private func track(_ start: Double, bpm: Int = 60, _ meter: Meter = Meter(.fourFour)) -> ClickTrack {
    ClickTrack(meter: meter, bpm: bpm, start: s(start))
}

private func facts(_ attempt: Attempt) -> PassFacts? {
    if case .pass(let facts) = attempt.facts { facts } else { nil }
}

@Suite("Up and down")
struct UpAndDownTests {
    @Test func itIsAScalesDrillForFreePracticeOnly() {
        #expect(DrillKind.all.contains(.upAndDown))
        #expect(DrillKind.upAndDown.id == "upAndDown")
        #expect(DrillKind.upAndDown.module == .scales)
        #expect(!DrillKind.upAndDown.isInSessions)
        #expect(DrillKind.upAndDown.usesMetronome)
        #expect(!DrillKind.upAndDown.needsSound)
        #expect(DrillKind.upAndDown.repeatTitle == "Restart")
        #expect(DrillKind.upAndDown.instructions.contains("Pick every note"))
        #expect(DrillKind.all.filter(\.usesMetronome).allSatisfy { $0.module == .scales })
    }

    @Test func aWholePass() {
        var drill = started()
        playPass(from: 4, &drill)
        #expect(drill.attempts.count == 23)
        #expect(drill.attempts.allSatisfy{ $0.firstRight })
        #expect(drill.attempts.map { $0.prompt.noteName }.prefix(6) == ["A", "C", "D", "E", "G", "A"])
        #expect(drill.attempts.first?.location == FretboardLocation(string: 0, fret: 5))
        #expect(drill.attempts[0].responseTime == s(0))
        #expect(drill.attempts[1].responseTime == s(1))
        #expect(drill.display?.result == .right)
        #expect(drill.display?.feedback == "Clean pass")
        #expect(drill.stats.prompts == 1)
    }

    @Test func theDisplayNamesTheScaleAndShowsTheShape() throws {
        let display = try #require(started().display)
        #expect(display.headline == "A minor pentatonic · up and down")
        #expect(display.subline == "G shape")
        #expect(display.markers.count == 12)
        #expect(display.markers.filter(\.isAnswer).map(\.label) == ["A", "A", "A"])
        #expect(!display.markers.contains { $0.isLastPlayed })
        let line = try #require(display.pass)
        #expect(line.notes.count == 23)
        #expect(line.notes.first?.height == 0)
        #expect(line.notes[11].height == 1)
        #expect(line.notes.map(\.state).prefix(2) == [.current, .waiting])
        #expect(line.settings.tempo == 60)
    }

    @Test func onlyTheLastNoteIsLitAndTheLineFillsIn() throws {
        var drill = started()
        play(45, at: 4, &drill)
        play(48, at: 5, &drill)
        let display = try #require(drill.display)
        #expect(display.markers.filter(\.isLastPlayed).map(\.location) == [FretboardLocation(string: 0, fret: 8)])
        #expect(display.pass?.notes.map(\.state).prefix(4) == [.found, .found, .current, .waiting])
        #expect(display.feedback == "Listening…")
    }

    @Test func inAnyTuningAndWithACapo() throws {
        for (preset, capo) in [(TuningPreset.dropD, 0), (.dadgad, 2), (.openG, 0), (.standard, 3)] {
            var drill = DrillKind.upAndDown.makeDrill(setup(preset, capo: capo))
            drill.handle(.start(at: s(0)))
            let count = try #require(drill.display?.pass?.notes.count)
            for index in 0..<count {
                let target = try #require(drill.prompt?.target)
                play(drill.fretboard.pitch(at: target).midi, at: 4 + Double(index), &drill)
            }
            #expect(drill.display?.feedback == "Clean pass")
        }
    }

    @Test func spelledByTheScale() {
        let drill = started { $0.scaleKind = .blues }
        #expect(drill.display?.markers.map(\.label).contains("E♭") == true)
        #expect(drill.display?.headline == "A blues · up and down")
        // The key moves to the scale's mode.
        #expect(started { $0.key = .major(.dFlat) }.display?.headline == "C♯ minor pentatonic · up and down")
    }

    @Test func aPositionThatIsntThereFallsBack() {
        func position(_ change: (inout DrillOptions) -> Void) -> Position.ID? { setup(change: change).position?.id }
        #expect(position { $0.position = .init(system: .caged, number: 5, octave: 1) } == .init(system: .caged, number: 5, octave: 1))
        // This octave up doesn't fit.
        #expect(position { $0.position = .init(system: .caged, number: 4, octave: 1); $0.key = .minor(.e) }
            == .init(system: .caged, number: 4))
        // Pentatonics have no 3NPS patterns.
        #expect(position { $0.positionSystem = .threeNotesPerString; $0.position = .init(system: .threeNotesPerString, number: 3) }
            == .init(system: .caged, number: 1))
    }

    @Test func aPositionThatDoesntFitTheNeckSaysSo() {
        var capoed = setup()
        capoed.fretboard = Fretboard(tuning: .standard, capo: 12)
        let reasons = (1...5).compactMap { number in
            capoed.options.position = .init(system: .caged, number: number)
            return DrillKind.upAndDown.makeDrill(capoed).nothingToPromptReason
        }
        #expect(!reasons.isEmpty)
    }
}

@Suite("Clicks and count-in")
struct PassClickTests {
    @Test func startAsksForClicksAndCountsIn() {
        var drill = started()
        #expect(drill.takeClicks() == [.start(track(0))])
        #expect(drill.takeClicks().isEmpty)
        #expect(drill.promptStart == s(4))
        #expect(drill.display?.pass?.countIn == 1)
        #expect(drill.display?.feedback == "Pick every note")
        drill.handle(.tick(at: s(2.5)))
        #expect(drill.display?.pass?.countIn == 3)
        drill.handle(.tick(at: s(4)))
        #expect(drill.display?.pass?.countIn == nil)
        #expect(drill.display?.feedback == "Listening…")
    }

    @Test func notesAreJudgedByWhenClicksAreHeard() {
        var drill = started()
        drill.handle(.clicksStarted(track(0.3)))
        drill.handle(.tick(at: s(0.2)))
        #expect(drill.display?.pass?.countIn == nil)
        #expect(drill.promptStart == s(4.3))
        play(45, at: 4.4, &drill)
        #expect(drill.attempts[0].responseTime == s(0.1))
        #expect(facts(drill.attempts[0])?.clickOffset == s(0.1))
    }

    @Test func wholeBarsAtLeastFourClicks() throws {
        let sixEight = try #require(TimeSignature(beats: 6, unit: 8))
        let twoFour = try #require(TimeSignature(beats: 2, unit: 4))
        #expect(started { $0.pass.meter = Meter(sixEight); $0.pass.tempo = 120 }.promptStart == s(3))
        var drill = started { $0.pass.meter = Meter(twoFour) }
        #expect(drill.promptStart == s(4))
        drill.handle(.tick(at: s(3)))
        #expect(drill.display?.pass?.countIn == 2)
    }

    @Test func countInNotesAreIgnored() {
        var drill = started()
        play(45, at: 2, &drill)
        play(45, at: 3.49, &drill)
        play(50, at: 3.8, &drill)
        #expect(drill.attempts.isEmpty)
        #expect(drill.phase == .waiting)
    }

    @Test func theFirstNoteMayBeHalfABeatEarly() {
        var drill = started()
        play(45, at: 3.6, &drill)
        #expect(drill.attempts.count == 1)
        #expect(drill.attempts[0].firstRight)
        #expect(drill.attempts[0].responseTime == s(0))
        #expect(facts(drill.attempts[0])?.clickOffset == s(-0.4))
        #expect(drill.display?.pass?.countIn == nil)
        play(48, at: 4.4, &drill)
        #expect(drill.attempts[1].responseTime == s(0.8))
    }

    @Test func halfABeatFollowsTheTempo() {
        var drill = started { $0.pass.tempo = 120 }
        play(45, at: 1.74, &drill)
        #expect(drill.attempts.isEmpty)
        play(45, at: 1.75, &drill)
        #expect(drill.attempts.count == 1)
        #expect(facts(drill.attempts[0])?.clickOffset == s(-0.25))
    }

    @Test func timingNeverMakesANoteWrong() {
        var drill = started()
        for (index, midi) in pass.enumerated() { play(midi, at: 4.4 + Double(index) * 2.7, &drill) }
        #expect(drill.display?.feedback == "Clean pass")
    }

    @Test func theClickRunsToTheEndOfTheBarThenTheNextCountIn() {
        var drill = started()
        _ = drill.takeClicks()
        // The last note is on click 26, beat 3 of its bar, which ends at 28 s.
        playPass(from: 4, &drill)
        #expect(drill.phase == .correct(FretboardLocation(string: 0, fret: 5)))
        drill.handle(.tick(at: s(27.9)))
        #expect(drill.display?.feedback == "Clean pass")
        drill.handle(.tick(at: s(28.01)))
        #expect(drill.phase == .waiting)
        #expect(drill.display?.pass?.countIn == 1)
        #expect(drill.display?.feedback == "Last pass: clean")
        #expect(drill.promptStart == s(32))
        // The same clicks, unbroken.
        #expect(drill.takeClicks().isEmpty)
        playPass(from: 32, &drill)
        #expect(drill.attempts.count == 46)
        #expect(drill.attempts[22].group?.number != drill.attempts[23].group?.number)
        #expect(drill.stats.prompts == 2)
    }

    @Test func aLastNoteJustBeforeADownbeatBelongsToTheBarItStarts() {
        var drill = started()
        for (index, midi) in pass.dropLast().enumerated() { play(midi, at: 4 + Double(index), &drill) }
        play(45, at: 27.95, &drill)
        drill.handle(.tick(at: s(28.2)))
        #expect(drill.phase != .waiting)
        drill.handle(.tick(at: s(32)))
        #expect(drill.promptStart == s(36))
    }

    @Test func clicksGoOnThroughAStall() {
        var drill = started()
        _ = drill.takeClicks()
        for time in stride(from: 4.0, to: 40, by: 0.5) { drill.handle(.tick(at: s(time))) }
        #expect(drill.takeClicks().isEmpty)
    }

    @Test func newSettingsApplyFromTheNextPass() throws {
        var drill = started()
        _ = drill.takeClicks()
        var settings = PassSettings()
        settings.tempo = 120
        drill.handle(.passSettings(settings, at: s(1)))
        #expect(drill.display?.pass?.settings.tempo == 60)
        playPass(from: 4, &drill)
        #expect(drill.takeClicks() == [.stop(at: s(28)), .start(track(28, bpm: 120))])
        // In the gap too.
        settings.meter = Meter(try #require(TimeSignature(beats: 3, unit: 4)))
        drill.handle(.passSettings(settings, at: s(27)))
        #expect(drill.takeClicks() == [.stop(at: s(28)), .start(track(28, bpm: 120, settings.meter))])
        drill.handle(.clicksStarted(track(28.1, bpm: 120, settings.meter)))
        drill.handle(.tick(at: s(28.2)))
        #expect(drill.promptStart == s(31.1))
        #expect(drill.display?.pass?.settings == settings)
        #expect(facts(drill.attempts[0])?.tempo == 60)
        play(45, at: 31.1, &drill)
        #expect(facts(drill.attempts[23])?.tempo == 120)
        #expect(facts(drill.attempts[23])?.beatsPerBar == 3)
    }

    @Test func aHoldBetweenPassesDelaysTheCountIn() {
        var drill = started()
        playPass(from: 4, &drill)
        _ = drill.takeClicks()
        #expect(drill.canHold)
        drill.handle(.hold(until: s(29.5)))
        #expect(drill.takeClicks() == [.stop(at: s(28)), .start(track(29.5))])
        drill.handle(.tick(at: s(29)))
        #expect(drill.phase != .waiting)
        drill.handle(.tick(at: s(29.5)))
        #expect(drill.promptStart == s(33.5))
    }

    @Test func stoppingStopsTheClicks() {
        var drill = started()
        _ = drill.takeClicks()
        drill.handle(.stop(at: s(3)))
        #expect(drill.takeClicks() == [.stop(at: s(3))])
        #expect(drill.phase == .idle)
        #expect(drill.display == nil)
    }
}

@Suite("Notes of a pass")
struct PassNoteTests {
    @Test func aWrongNoteIsNamedAndThePassWaits() {
        var drill = started()
        play(45, at: 4, &drill)
        play(50, at: 5, &drill)
        #expect(drill.phase == .wrong(PitchClass(2)))
        #expect(drill.display?.feedback == "You played D")
        #expect(drill.display?.result == .wrong)
        play(60, at: 5.5, &drill)
        #expect(drill.display?.feedback == "You played C, in another octave")
        #expect(drill.display?.markers.filter(\.isLastPlayed).map(\.label) == ["A"])
        play(48, at: 6, &drill)
        #expect(drill.attempts[1].wrongAnswers == [.pitch(Pitch(50)), .pitch(Pitch(60))])
        #expect(drill.attempts[1].responseTime == s(2))
        #expect(drill.phase == .waiting)
    }

    @Test func aNoteIsRevealedAfterFiveSecondsAndThePassMovesOn() {
        var drill = started()
        #expect(drill.timeLimit == s(5))
        drill.handle(.tick(at: s(9.1)))
        #expect(drill.attempts.isEmpty)
        drill.handle(.tick(at: s(9.2)))
        #expect(drill.attempts.map(\.outcome) == [.timedOut])
        #expect(drill.display?.result == .timedOut)
        #expect(drill.display?.feedback == "Time’s up: it was A")
        #expect(drill.display?.markers.filter(\.isLastPlayed).map(\.location) == [FretboardLocation(string: 0, fret: 5)])
        #expect(drill.display?.pass?.notes.map(\.state).prefix(2) == [.timedOut, .current])
        // The next note's time runs from the timeout.
        play(48, at: 9.5, &drill)
        #expect(drill.attempts[1].responseTime == s(0.5))
        drill.handle(.tick(at: s(14.7)))
        #expect(drill.attempts.count == 3)
        #expect(facts(drill.attempts[0])?.clickOffset == nil)
    }

    @Test func aNoteInTimeButHeardLateCounts() {
        var drill = started()
        drill.handle(.tick(at: s(9.1)))
        drill.handle(.played(Pitch(45), onset: s(8.98), at: s(9.11)))
        #expect(drill.attempts.map(\.outcome) == [.answered])
    }

    @Test func theLastNoteTimingOutEndsThePass() {
        var drill = started()
        for (index, midi) in pass.dropLast().enumerated() { play(midi, at: 4 + Double(index), &drill) }
        drill.handle(.tick(at: s(30.2)))
        #expect(drill.phase == .timedOut)
        #expect(drill.display?.feedback == "Pass done · 1 revealed")
        drill.handle(.tick(at: s(32)))
        #expect(drill.phase == .waiting)
        #expect(drill.promptStart == s(36))
    }

    @Test func skipDropsTheRestOfThePass() {
        var drill = started()
        play(45, at: 4, &drill)
        _ = drill.takeClicks()
        drill.handle(.skip(at: s(5)))
        #expect(drill.attempts.map(\.outcome) == [.answered, .skipped])
        #expect(drill.attempts.map { $0.group?.place } == [0, 1])
        #expect(drill.takeClicks() == [.start(track(5))])
        #expect(drill.promptStart == s(9))
        #expect(drill.display?.pass?.notes.first?.state == .current)
        play(45, at: 9, &drill)
        #expect(drill.attempts[2].group?.number != drill.attempts[1].group?.number)
    }

    @Test func skipBetweenPassesOnlyEndsTheWait() {
        var drill = started()
        playPass(from: 4, &drill)
        drill.handle(.skip(at: s(27)))
        #expect(drill.attempts.count == 23)
        #expect(drill.promptStart == s(31))
    }

    @Test func repeatRestartsThePass() {
        var drill = started()
        play(45, at: 4, &drill)
        play(50, at: 5, &drill)
        _ = drill.takeClicks()
        drill.handle(.repeat(at: s(6)))
        #expect(drill.attempts.count == 1)
        #expect(drill.takeClicks() == [.start(track(6))])
        #expect(drill.phase == .waiting)
        #expect(drill.display?.markers.contains { $0.isLastPlayed } == false)
        play(45, at: 10, &drill)
        #expect(drill.attempts[1].firstRight)
        #expect(drill.attempts.map { $0.group?.place } == [0, 0])
        #expect(drill.attempts[0].group?.number != drill.attempts[1].group?.number)
    }

    @Test func resumeRestartsThePassWithACountIn() {
        var drill = started()
        play(45, at: 4, &drill)
        _ = drill.takeClicks()
        drill.handle(.pause(at: s(5)))
        #expect(drill.takeClicks() == [.stop(at: s(5))])
        #expect(drill.display == nil)
        #expect(drill.prompt == nil)
        #expect(drill.resumesSamePrompt)
        play(48, at: 6, &drill)
        drill.handle(.tick(at: s(30)))
        #expect(drill.attempts.count == 1)
        drill.handle(.resume(at: s(40)))
        #expect(drill.takeClicks() == [.start(track(40))])
        #expect(drill.promptStart == s(44))
        #expect(drill.prompt?.noteName == "A")
        playPass(from: 44, &drill)
        #expect(drill.passes.map(\.isComplete) == [false, true])
    }

    @Test func resumeAfterAPassGivesTheNext() {
        var drill = started()
        playPass(from: 4, &drill)
        drill.handle(.pause(at: s(27)))
        #expect(!drill.resumesSamePrompt)
        drill.handle(.resume(at: s(30)))
        #expect(drill.promptStart == s(34))
    }

    @Test func everyNoteIsLoggedWithThePassesFacts() throws {
        var drill = started()
        playPass(from: 4.05, &drill)
        #expect(drill.attemptsToLog.count == 23)
        #expect(drill.attempts.map { $0.group?.place } == Array(0..<23))
        #expect(drill.attempts.allSatisfy { $0.group?.size == 23 && $0.group?.number == drill.attempts[0].group?.number })
        #expect(drill.attempts.allSatisfy { attempt in
            facts(attempt) == PassFacts(scale: Scale(.minorPentatonic, tonic: .a), position: .init(system: .caged, number: 5),
                                        startDegree: .init(1), tempo: 60, beatsPerBar: 4, beatUnit: 4, fadeStage: .shown,
                                        hinted: false, clickOffset: .milliseconds(50))
        })
    }

    @Test func completeAndCleanAreWorkedOutFromTheAttempts() {
        var drill = started()
        playPass(from: 4, &drill)
        #expect(drill.passes.map(\.isClean) == [true])
        drill.handle(.tick(at: s(28)))
        // A wrong note.
        play(50, at: 32, &drill)
        playPass(from: 33, &drill)
        #expect(drill.display?.feedback == "Pass done · 1 wrong")
        drill.handle(.tick(at: s(56)))
        // Cut short.
        play(45, at: 60, &drill)
        drill.handle(.skip(at: s(61)))
        #expect(drill.passes.map(\.isComplete) == [true, true, false])
        #expect(drill.passes.map(\.isClean) == [true, false, false])
    }

    @Test func startingAgainForgetsThePasses() {
        var drill = started()
        play(45, at: 4, &drill)
        drill.handle(.stop(at: s(5)))
        drill.handle(.start(at: s(6)))
        #expect(drill.attempts.isEmpty)
        #expect(drill.promptStart == s(10))
    }
}
