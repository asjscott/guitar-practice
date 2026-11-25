import Testing
import TheoryCore
import PracticeCore

/// Note by note: response times in seconds, so that all but the first are gaps between onsets.
private func result(_ times: [Double], tempo: Int = 60, wrongAt: Int? = nil, timeoutAt: Int? = nil, skipAt: Int? = nil,
                    hinted: Bool = false, size: Int? = nil) -> PassResult {
    let location = FretboardLocation(string: 0, fret: 5)
    let prompt = NotePrompt(name: Key.minor(.a).tonic, string: 0, target: location)
    let facts = PassFacts(scale: Scale(.minorPentatonic, tonic: .a), position: .init(system: .caged, number: 5),
                          startDegree: .init(1), tempo: tempo, beatsPerBar: 4, beatUnit: 4, fadeStage: .shown,
                          hinted: hinted, clickOffset: nil)
    return PassResult.passes(in: times.enumerated().map { index, time in
        let outcome: Attempt.Outcome = index == timeoutAt ? .timedOut : index == skipAt ? .skipped : .answered
        let isAnswered = outcome == .answered
        return Attempt(prompt: prompt, outcome: outcome, responseTime: isAnswered ? s(time) : nil,
                       wrongAnswers: index == wrongAt ? [.pitch(Pitch(50))] : [], location: isAnswered ? location : nil,
                       group: AttemptGroup(number: 0, size: size ?? times.count, place: index), facts: .pass(facts))
    })[0]
}

private let keptUp = result([0, 1, 1, 1, 1])
private let notClean = result([0, 1, 1, 1, 1], wrongAt: 2)
private let cutShort = result([0, 1], wrongAt: 1, size: 5)

private func steps(_ results: PassResult...) -> [Int] {
    var ladder = TempoLadder()
    return results.map { ladder.step(after: $0) }
}

@Suite("Tempo ladder")
struct TempoLadderTests {
    @Test func aCleanPassThatKeptUpAddsFour() {
        #expect(steps(keptUp, keptUp) == [4, 4])
    }

    @Test func withinATenthOfTheClicksKeepsUp() {
        // 4 beats at 60 are 4 s: up to 4.4 s.
        #expect(steps(result([0, 1.125, 1.125, 1.125, 1])) == [4])
        #expect(steps(result([0, 1.125, 1.125, 1.125, 1.0625])) == [0])
        // At 120, 2 s: up to 2.2 s.
        #expect(steps(result([0, 0.5, 0.5, 0.5, 0.6875], tempo: 120)) == [4])
        #expect(steps(result([0, 0.5, 0.5, 0.5, 0.75], tempo: 120)) == [0])
    }

    @Test func aLateFirstNoteDoesntCount() {
        #expect(steps(result([3, 1, 1, 1, 1])) == [4])
    }

    @Test func twoInARowThatArentCleanTakeFourOffAndTheCountStartsAgain() {
        #expect(steps(notClean, notClean, notClean, notClean) == [0, -4, 0, -4])
        #expect(steps(result([0, 1, 5], timeoutAt: 2), result([0, 1, 1], hinted: true)) == [0, -4])
    }

    @Test func aCleanPassBreaksTheRowEvenIfItDidntKeepUp() {
        #expect(steps(notClean, keptUp, notClean) == [0, 4, 0])
        #expect(steps(notClean, result([0, 2, 2, 2, 2]), notClean) == [0, 0, 0])
    }

    @Test func passesCutShortCountNeitherWay() {
        #expect(steps(notClean, cutShort, notClean) == [0, 0, -4])
        #expect(steps(cutShort, cutShort, result([0, 1, 1], skipAt: 2)) == [0, 0, 0])
    }

    @Test func temposStayWithinRange() {
        var settings = PassSettings()
        settings.tempo = 200
        #expect(settings.tempo == 160)
        settings.tempo = 7
        #expect(settings.tempo == 40)
    }

    @Test func theSettingsTextNamesTheBeat() throws {
        var settings = PassSettings()
        settings.tempo = 72
        #expect(settings.text == "♩ = 72 · 4/4")
        settings.meter = Meter(try #require(TimeSignature(beats: 6, unit: 8)))
        #expect(settings.text == "♪ = 72 · 6/8")
    }
}

@Suite("Evenness")
struct EvennessTests {
    @Test func theStandardDeviationOfTheGaps() throws {
        #expect(result([0.4, 1, 1, 1]).evenness == s(0))
        // Whatever the first note's time.
        let uneven = result([0.4, 0.9, 1.1, 0.9, 1.1])
        let evenness = try #require(uneven.evenness)
        #expect(abs(evenness / .milliseconds(1) - 100) < 0.001)
        // Timing only, however slow.
        #expect(result([0, 3, 3, 3]).evenness == s(0))
    }

    @Test func noneAfterAWrongNoteATimeoutOrAPassCutShort() {
        #expect(result([0, 1, 1], wrongAt: 1).evenness == nil)
        #expect(result([0, 1, 1], timeoutAt: 1).evenness == nil)
        #expect(result([0, 1, 1], skipAt: 2).evenness == nil)
        #expect(result([0, 1], size: 5).evenness == nil)
        #expect(result([0], size: 1).evenness == nil)
    }

    @Test func aHintLeavesIt() { #expect(result([0, 1, 1], hinted: true).evenness == s(0)) }
}

/// A minor pentatonic, G shape.
private let up = [45, 48, 50, 52, 55, 57, 60, 62, 64, 67, 69, 72]
private let pass = up + up.dropLast().reversed()

@Suite("Tempo of a drill")
struct DrillTempoTests {
    private func started(_ change: (inout PassSettings) -> Void = { _ in }) -> any Drill {
        var options = DrillOptions()
        options.key = .minor(.a)
        options.scaleKind = .minorPentatonic
        options.position = Position.ID(system: .caged, number: CAGEDShape.g.number)
        change(&options.pass)
        var drill = DrillKind.upAndDown.makeDrill(DrillSetup(fretboard: Fretboard(tuning: .standard), options: options, seed: 1))
        drill.handle(.start(at: s(0)))
        return drill
    }

    /// Plays the pass that is up at its tempo, from its beat 1, then moves into the next's count-in.
    private func playPass(_ drill: inout any Drill, wrong: Bool = false, afterFirstNote: (inout any Drill) -> Void = { _ in }) {
        guard let start = drill.promptStart, let tempo = drill.display?.pass?.settings.tempo else { return }
        for (index, midi) in pass.enumerated() {
            let onset = start + .seconds(60) * index / tempo
            if wrong, index == 1 {
                drill.handle(.played(Pitch(50), onset: onset - .milliseconds(200), at: onset - .milliseconds(100)))
            }
            drill.handle(.played(Pitch(midi), onset: onset, at: onset + .milliseconds(130)))
            if index == 0 { afterFirstNote(&drill) }
        }
        // The last bar ends 24 beats after beat 1.
        drill.handle(.tick(at: start + .seconds(60) * 25 / tempo))
    }

    private func change(_ drill: inout any Drill, at time: Duration, _ change: (inout PassSettings) -> Void) {
        guard var settings = drill.passSettings else { return }
        change(&settings)
        drill.handle(.passSettings(settings, at: time))
    }

    @Test func theNextPassIsFasterWithItsOwnClicks() {
        var drill = started()
        #expect(drill.passSettings?.tempo == 60)
        _ = drill.takeClicks()
        playPass(&drill)
        #expect(drill.passSettings?.tempo == 64)
        #expect(drill.display?.pass?.settings.tempo == 64)
        // Beat 1 at 4 s; the last bar ends at 28 s.
        #expect(drill.takeClicks() == [.stop(at: s(28)), .start(ClickTrack(meter: Meter(.fourFour), bpm: 64, start: s(28)))])
    }

    @Test func twoPassesThatArentCleanSlowIt() {
        var drill = started()
        playPass(&drill, wrong: true)
        #expect(drill.passSettings?.tempo == 60)
        playPass(&drill, wrong: true)
        #expect(drill.passSettings?.tempo == 56)
    }

    @Test func holdTurnsItOff() {
        var drill = started { $0.holdsTempo = true }
        for wrong in [false, true, true] { playPass(&drill, wrong: wrong) }
        #expect(drill.passSettings?.tempo == 60)
    }

    @Test func itStaysInRange() {
        var fast = started { $0.tempo = 158 }
        playPass(&fast)
        #expect(fast.passSettings?.tempo == 160)
        var slow = started { $0.tempo = 40 }
        for _ in 0..<2 { playPass(&slow, wrong: true) }
        #expect(slow.passSettings?.tempo == 40)
    }

    @Test func aManualChangeIsWhereItCarriesOnFrom() {
        var drill = started()
        // The pass going, at the old tempo, doesn't move it.
        playPass(&drill) { drill in
            change(&drill, at: s(4.5)) { $0.tempo = 100 }
            #expect(drill.display?.pass?.settings.tempo == 60)
        }
        #expect(drill.display?.pass?.settings.tempo == 100)
        playPass(&drill)
        #expect(drill.display?.pass?.settings.tempo == 104)
    }

    @Test func aManualChangeStartsTheCountAgain() {
        var drill = started()
        playPass(&drill, wrong: true)
        change(&drill, at: s(29.5)) { $0.tempo = 80 }
        drill.handle(.repeat(at: s(30)))
        playPass(&drill, wrong: true)
        #expect(drill.passSettings?.tempo == 80)
        playPass(&drill, wrong: true)
        #expect(drill.passSettings?.tempo == 76)
    }

    @Test func otherSettingsLeaveItAlone() {
        var drill = started()
        playPass(&drill, wrong: true)
        playPass(&drill, wrong: true) { drill in
            change(&drill, at: s(32.5)) { $0.fadeStage = .faded }
        }
        #expect(drill.passSettings?.tempo == 56)
        #expect(drill.passSettings?.fadeStage == .faded)
    }

    /// The change's own time can end the pass, before the change is made.
    @Test func otherSettingsDontUndoTheLadder() {
        var drill = started()
        playPass(&drill, wrong: true)
        let start = s(32)
        for (index, midi) in pass.dropLast().enumerated() {
            drill.handle(.played(Pitch(midi), onset: start + s(Double(index)), at: start + s(Double(index) + 0.1)))
        }
        // The last note's 5 s are over.
        change(&drill, at: start + s(21 + 5.2)) { $0.fadeStage = .faded }
        #expect(drill.passSettings?.tempo == 56)
    }

    @Test func evennessShowsAfterThePassAndInTheNextCountIn() {
        var drill = started()
        #expect(drill.display?.pass?.evenness == nil)
        playPass(&drill) { #expect($0.display?.pass?.evenness == nil) }
        #expect(drill.display?.pass?.evenness == .zero)
        #expect(drill.display?.pass?.evennessText == "evenness 0 ms")
        playPass(&drill, wrong: true) { #expect($0.display?.pass?.evenness == nil) }
        #expect(drill.display?.pass?.evenness == nil)
    }

    @Test func drillsWithoutPassesHaveNone() {
        #expect(DrillKind.notePlayIt.makeDrill(DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1)).passSettings == nil)
    }
}
