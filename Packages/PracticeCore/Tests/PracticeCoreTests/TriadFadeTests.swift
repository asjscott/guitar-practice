import Testing
import TheoryCore
import PracticeCore

private let aMinorSecond = TriadFacts(triad: Triad(.minor, root: .a), inversion: .second, stringSet: .dGB)
private let shape = FadeLevels.VoicingShape(tuning: .standard, quality: .minor, inversion: .second, stringSet: .dGB)

private func reached(_ stage: FadeStage, _ shape: FadeLevels.VoicingShape = shape) -> FadeLevels {
    var stages = FadeLevels()
    let steps: [FadeStage] = stage == .shown ? [] : stage == .faded ? [.shown] : [.shown, .faded]
    for step in steps { stages.add(voicing: voicing(at: step, shape)) }
    return stages
}

/// The notes of a voicing: clean, unless something is said to go wrong.
private func voicing(at stage: FadeStage, _ shape: FadeLevels.VoicingShape = shape, wrongAt: Int? = nil,
                     hintedAt: Int? = nil, endingWith last: Attempt.Outcome = .answered, count: Int = 3) -> [FadeLevels.VoicingNote] {
    (0..<count).map { place in
        let outcome = place == count - 1 ? last : .answered
        return FadeLevels.VoicingNote(shape: shape, stage: stage, hinted: hintedAt.map { place >= $0 } ?? false, place: place,
                                      outcome: outcome, firstRight: outcome == .answered && place != wrongAt)
    }
}

private func stage(after voicings: [FadeLevels.VoicingNote]...) -> FadeStage {
    var stages = FadeLevels()
    for voicing in voicings { stages.add(voicing: voicing) }
    return stages.stage(of: shape)
}

@Suite("Fade of triads")
struct TriadFadeFoldTests {
    @Test func itStartsShownAndCleanVoicingsHideIt() {
        #expect(stage() == .shown)
        #expect(stage(after: voicing(at: .shown)) == .faded)
        #expect(stage(after: voicing(at: .shown), voicing(at: .faded)) == .hidden)
        #expect(stage(after: voicing(at: .shown), voicing(at: .faded), voicing(at: .hidden)) == .hidden)
    }

    @Test func anyOtherGoesBackOne() {
        let hidden = reached(.hidden)
        for unclean in [voicing(at: .hidden, wrongAt: 1), voicing(at: .hidden, hintedAt: 2),
                        voicing(at: .hidden, endingWith: .timedOut, count: 1), voicing(at: .hidden, endingWith: .timedOut)] {
            var stages = hidden
            stages.add(voicing: unclean)
            #expect(stages.stage(of: shape) == .faded)
        }
        #expect(stage(after: voicing(at: .shown, wrongAt: 0)) == .shown)
    }

    @Test func oneSkippedOrCutShortOrAtAnotherStageCountsNeitherWay() {
        for other in [voicing(at: .shown, endingWith: .skipped), voicing(at: .shown, count: 2), voicing(at: .hidden), []] {
            #expect(stage(after: other) == .shown)
        }
    }

    @Test func shapesAreSeparate() {
        var stages = reached(.faded)
        var others = [FadeLevels.VoicingShape](repeating: shape, count: 4)
        others[0].tuning = TuningPreset.dropD.tuning
        others[1].quality = .major
        others[2].inversion = .first
        others[3].stringSet = .gBE
        #expect(others.map(stages.stage(of:)) == [.shown, .shown, .shown, .shown])
        stages.add(voicing: voicing(at: .shown, others[0]))
        #expect(stages.stage(of: shape) == .faded)
    }

    @Test func theLogIsSplitIntoVoicings() {
        // A climb's are in one group. One a pause cut short starts again.
        let again = voicing(at: .shown, count: 2) + voicing(at: .shown) + voicing(at: .faded)
        #expect(FadeLevels(log: [(group: Int, note: FadeLevels.Note)](), voicings: again.map { (group: 1, note: $0) }).stage(of: shape) == .hidden)
        // One a stop cut short isn't finished by another group's notes.
        let cut = voicing(at: .shown, count: 2).map { (group: 1, note: $0) } + voicing(at: .shown).suffix(1).map { (group: 2, note: $0) }
        #expect(FadeLevels(log: [(group: Int, note: FadeLevels.Note)](), voicings: cut).stage(of: shape) == .shown)
    }
}

private func setup(_ stages: FadeLevels = FadeLevels(), key: Key = .major(.c), override: FadeStage? = nil, capo: Int = 0,
                   seed: UInt64) -> DrillSetup {
    var options = DrillOptions()
    options.key = key
    options.frets = 0...22
    options.stringSets = [.dGB]
    options.inversions = [.second]
    options.triadFade = override
    var setup = DrillSetup(fretboard: Fretboard(tuning: .standard, capo: capo), options: options, seed: seed)
    setup.fadeLevels = stages
    return setup
}

/// A run whose first prompt is for A minor's 2nd inversion on D-G-B: 2 2 1 (52 57 60), or an octave up.
private func asking(_ stages: FadeLevels = FadeLevels(), override: FadeStage? = nil) -> any Drill {
    for seed in UInt64(0)..<500 {
        var drill = DrillKind.triadPlayIt.makeDrill(setup(stages, override: override, seed: seed))
        drill.handle(.start(at: s(0)))
        if drill.display?.headline == aMinorSecond.text { return drill }
    }
    fatalError("No seed asks for it")
}

private func play(_ midi: Int, at time: Double, _ drill: inout any Drill) {
    drill.handle(.played(Pitch(midi), onset: s(time), at: s(time + 0.1)))
}

private let low = [52, 57, 60]

@Suite("Triad → play it fading")
struct TriadPlayItFadeTests {
    @Test func shownHasTheLowestVoicingsDotsAndNames() throws {
        let display = try #require(asking().display)
        #expect(display.markers == [
            .init(location: FretboardLocation(string: 2, fret: 2), label: "E", isAnswer: false),
            .init(location: FretboardLocation(string: 3, fret: 2), label: "A", isAnswer: true),
            .init(location: FretboardLocation(string: 4, fret: 1), label: "C", isAnswer: false),
        ])
        #expect(display.chips.map(\.text) == ["E", "A", "C"])
        #expect(display.chips.map(\.state) == [.current, .waiting, .waiting])
    }

    @Test func theLastNotePlayedIsRinged() throws {
        var drill = asking()
        play(52, at: 1, &drill)
        let display = try #require(drill.display)
        #expect(display.markers.map(\.isLastPlayed) == [true, false, false])
        #expect(display.markers.map(\.label) == ["E", "A", "C"])
    }

    @Test func anotherVoicingIsRightAndThenShown() throws {
        var drill = asking()
        play(64, at: 1, &drill)
        #expect(drill.attempts.map(\.outcome) == [.answered])
        #expect(try #require(drill.display).markers.map(\.location.fret) == [14, 14, 13])
    }

    @Test func fadedHasFaintDotsWithoutNames() throws {
        var drill = asking(reached(.faded))
        let display = try #require(drill.display)
        #expect(display.markers.map(\.label) == ["", "", ""])
        #expect(display.markers.allSatisfy { $0.isFaint })
        #expect(display.chips.map(\.text) == ["?", "?", "?"])
        play(52, at: 1, &drill)
        #expect(drill.display?.markers.map(\.isFaint) == [false, true, true])
        #expect(drill.display?.markers.map(\.label) == ["E", "", ""])
        #expect(drill.display?.chips.map(\.text) == ["E", "?", "?"])
    }

    @Test func hiddenHasNone() {
        #expect(asking(reached(.hidden)).display?.markers == [])
        #expect(asking(override: .hidden).display?.markers == [])
    }

    @Test func shownIsNotTimedAndTheOthersAre() {
        var drill = asking()
        #expect(drill.timeRemaining(at: s(1)) == nil)
        drill.handle(.tick(at: s(100)))
        #expect(drill.attempts.isEmpty && drill.phase == .waiting)
        play(52, at: 101, &drill)
        #expect(drill.attempts.map(\.responseTime) == [s(101)])
        for stage in [FadeStage.faded, .hidden] {
            var timed = asking(reached(stage))
            #expect(timed.timeRemaining(at: s(1)) == s(9))
            timed.handle(.tick(at: s(10.3)))
            #expect(timed.phase == .timedOut)
        }
    }

    @Test func aHintShowsItWhileHeldAndIsLogged() {
        var drill = asking(reached(.hidden))
        play(52, at: 1, &drill)
        drill.handle(.hint(isShown: true, at: s(2)))
        #expect(drill.display?.markers.map(\.label) == ["E", "A", "C"])
        // Still timed.
        #expect(drill.timeRemaining(at: s(2)) == s(9))
        drill.handle(.hint(isShown: false, at: s(3)))
        #expect(drill.display?.markers.map(\.label) == ["E"])
        play(57, at: 4, &drill)
        let facts = drill.attempts.map { if case .triad(let facts) = $0.facts { facts.hinted } else { false } }
        #expect(facts == [false, true])
        play(60, at: 5, &drill)
        #expect(drill.fadeLevels?.stage(of: shape) == .faded)
    }

    @Test func pausingEndsAHint() {
        var drill = asking(override: .hidden)
        drill.handle(.hint(isShown: true, at: s(1)))
        drill.handle(.pause(at: s(2)))
        drill.handle(.resume(at: s(3)))
        #expect(drill.display?.markers == [])
    }

    @Test func aCleanOneMovesOnAndIsLoggedAtItsStage() {
        var drill = asking()
        for (index, midi) in low.enumerated() { play(midi, at: 1 + Double(index), &drill) }
        #expect(drill.fadeLevels?.stage(of: shape) == .faded)
        let stages = drill.attempts.map { attempt -> FadeStage? in
            guard case .triad(let facts) = attempt.facts else { return nil }
            return facts.fadeStage
        }
        #expect(stages == [.shown, .shown, .shown])
        let notes = drill.attemptsToLog.compactMap { attempt in
            FadeLevels.VoicingNote(attempt, in: .standard).map { (group: attempt.group?.number ?? -1, note: $0) }
        }
        #expect(FadeLevels(log: [(group: Int, note: FadeLevels.Note)](), voicings: notes).stage(of: shape) == .faded)
    }

    @Test func aSkippedOneLeavesIt() {
        var drill = asking(reached(.faded))
        play(52, at: 1, &drill)
        drill.handle(.skip(at: s(2)))
        #expect(drill.fadeLevels?.stage(of: shape) == .faded)
    }

    @Test func anOverrideDoesntMoveIt() {
        var drill = asking(override: .hidden)
        for (index, midi) in low.enumerated() { play(midi, at: 1 + Double(index), &drill) }
        #expect(drill.fadeLevels?.stage(of: shape) == .shown)
    }

    @Test func resumingTakesUpWhatWasReachedMeanwhile() {
        var drill = asking()
        drill.handle(.pause(at: s(1)))
        var all = FadeLevels()
        for quality in Triad.Quality.allCases {
            let shape = FadeLevels.VoicingShape(tuning: .standard, quality: quality, inversion: .second, stringSet: .dGB)
            all.add(voicing: voicing(at: .shown, shape))
        }
        drill.handle(.fadeLevels(all))
        drill.handle(.resume(at: s(2)))
        #expect(drill.display?.markers.allSatisfy { $0.isFaint } == true)
    }

    @Test func aMinorAndDMinorShareIt() {
        // A chord of another root, in the same shape.
        for seed in UInt64(0)..<500 {
            var drill = DrillKind.triadPlayIt.makeDrill(setup(reached(.hidden), seed: seed))
            drill.handle(.start(at: s(0)))
            guard drill.display?.headline == "D minor · 2nd inversion" else { continue }
            #expect(drill.display?.markers == [])
            return
        }
        Issue.record("No seed asks for D minor")
    }
}

@Suite("Inversions fading")
struct InversionsFadeTests {
    /// A minor on D-G-B up to fret 12: 2nd inversion, root position, 1st inversion, and back.
    private func climbing(_ stages: FadeLevels = FadeLevels()) -> any Drill {
        for seed in UInt64(0)..<500 {
            var options = DrillOptions()
            options.stringSets = [.dGB]
            var setup = DrillSetup(fretboard: Fretboard(tuning: .standard), options: options, seed: seed)
            setup.fadeLevels = stages
            var drill = DrillKind.inversions.makeDrill(setup)
            drill.handle(.start(at: s(0)))
            if drill.display?.headline.hasPrefix("A minor · ") == true { return drill }
        }
        fatalError("No seed asks for it")
    }

    private func play(_ voicing: [Int], from start: Double, _ drill: inout any Drill) {
        for (index, midi) in voicing.enumerated() {
            drill.handle(.played(Pitch(midi), onset: s(start + Double(index)), at: s(start + Double(index) + 0.1)))
        }
        drill.handle(.tick(at: s(start + 4)))
    }

    private let root = [57, 60, 64], first = [60, 64, 69]

    @Test func theWayBackUsesWhatTheWayUpReached() {
        var drill = climbing()
        #expect(drill.display?.chips.map(\.text) == ["E", "A", "C"])
        #expect(drill.timeRemaining(at: s(1)) == nil)
        play(low, from: 1, &drill)
        play(root, from: 6, &drill)
        #expect(drill.display?.markers.map(\.isFaint) == [false, false, false])
        play(first, from: 11, &drill)
        // Root position again, now faded.
        #expect(drill.display?.markers.map(\.isFaint) == [true, true, true])
        #expect(drill.fadeLevels?.stage(of: shape) == .faded)
    }

    @Test func aVoicingResumedStartsAfresh() {
        var drill = climbing()
        drill.handle(.played(Pitch(50), onset: s(1), at: s(1.1)))
        drill.handle(.played(Pitch(52), onset: s(2), at: s(2.1)))
        drill.handle(.pause(at: s(3)))
        drill.handle(.resume(at: s(4)))
        play(low, from: 5, &drill)
        #expect(drill.fadeLevels?.stage(of: shape) == .faded)
        let notes = drill.attemptsToLog.compactMap { attempt in
            FadeLevels.VoicingNote(attempt, in: .standard).map { (group: attempt.group?.number ?? -1, note: $0) }
        }
        #expect(FadeLevels(log: [(group: Int, note: FadeLevels.Note)](), voicings: notes).stage(of: shape) == .faded)
    }
}

@Suite("Triads fading in a session")
struct SessionTriadFadeTests {
    @Test func theBlocksCarryItOnAndTakeHints() {
        let block = SessionBlock(kind: .triadPlayIt, length: s(180))
        var stages = FadeLevels()
        for quality in Triad.Quality.allCases {
            stages.add(voicing: voicing(at: .shown, .init(tuning: .standard, quality: quality, inversion: .second, stringSet: .dGB)))
        }
        var player = SessionPlayer(blocks: [block, block], setup: setup(stages, seed: 1))
        player.handle(.start(at: s(0)))
        player.handle(.next(at: s(0)))
        #expect(player.display?.markers.allSatisfy { $0.isFaint } == true)
        player.handle(.hint(isShown: true, at: s(1)))
        #expect(player.display?.markers.contains { $0.isFaint } == false)
        player.handle(.next(at: s(2)))
        player.handle(.next(at: s(3)))
        #expect(player.display?.markers.allSatisfy { $0.isFaint } == true)
    }
}
