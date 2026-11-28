import Testing
import TheoryCore
import PracticeCore

private let aMinorSecond = TriadFacts(triad: Triad(.minor, root: .a), inversion: .second, stringSet: .dGB)
private let shape = FadeLevels.VoicingShape(tuning: .standard, quality: .minor, inversion: .second, stringSet: .dGB)

/// Clean voicings from level 0 up to `level`, each in a run of its own.
private func reached(_ level: Int, _ shape: FadeLevels.VoicingShape = shape) -> FadeLevels {
    var levels = FadeLevels()
    for number in 0..<level {
        levels.add(voicing: voicing(at: number, shape))
        levels.endRun()
    }
    return levels
}

/// The notes of a voicing: clean, unless something is said to go wrong.
private func voicing(at level: Int, _ shape: FadeLevels.VoicingShape = shape, wrongAt: Int? = nil,
                     hintedAt: Int? = nil, endingWith last: Attempt.Outcome = .answered, count: Int = 3) -> [FadeLevels.VoicingNote] {
    (0..<count).map { place in
        let outcome = place == count - 1 ? last : .answered
        return FadeLevels.VoicingNote(shape: shape, level: FadeLevel(level), hinted: hintedAt.map { place >= $0 } ?? false,
                                      place: place, outcome: outcome, firstRight: outcome == .answered && place != wrongAt)
    }
}

/// Each voicing in a run of its own.
private func level(after voicings: [FadeLevels.VoicingNote]...) -> Int {
    var levels = FadeLevels()
    for voicing in voicings {
        levels.add(voicing: voicing)
        levels.endRun()
    }
    return levels.level(of: shape).number
}

@Suite("Fade levels of triads")
struct TriadFadeFoldTests {
    @Test func itStartsAtZeroAndEachCleanVoicingMovesItUpOne() {
        #expect(level() == 0)
        #expect(level(after: voicing(at: 0)) == 1)
        #expect(level(after: voicing(at: 0), voicing(at: 1)) == 2)
        #expect(reached(6).level(of: shape) == .last)
        #expect(level(after: voicing(at: 0), voicing(at: 1), voicing(at: 2), voicing(at: 3), voicing(at: 4),
                      voicing(at: 5), voicing(at: 6)) == 6)
    }

    @Test func anyOtherMovesItDownOne() {
        for unclean in [voicing(at: 3, wrongAt: 1), voicing(at: 3, hintedAt: 2),
                        voicing(at: 3, endingWith: .timedOut, count: 1), voicing(at: 3, endingWith: .timedOut)] {
            var levels = reached(3)
            levels.add(voicing: unclean)
            levels.endRun()
            #expect(levels.level(of: shape) == FadeLevel(2))
        }
        #expect(level(after: voicing(at: 0, wrongAt: 0)) == 0)
    }

    @Test func oneSkippedOrCutShortOrAtAnotherLevelCountsNeitherWay() {
        for other in [voicing(at: 0, endingWith: .skipped), voicing(at: 0, count: 2), voicing(at: 4), []] {
            #expect(level(after: other) == 0)
        }
    }

    @Test func voicingsLoggedAtAStageMoveAsTheStagesDid() {
        func old(_ stage: FadeStage, wrong: Bool = false) -> [FadeLevels.VoicingNote] {
            (0..<3).map {
                FadeLevels.VoicingNote(shape: shape, stage: stage, hinted: false, place: $0, outcome: .answered,
                                       firstRight: !wrong)
            }
        }
        #expect(level(after: old(.shown)) == 2)
        #expect(level(after: old(.shown), old(.faded)) == 6)
        #expect(level(after: old(.shown), old(.faded), old(.hidden, wrong: true)) == 2)
        // Then on by levels.
        #expect(level(after: old(.shown), voicing(at: 2)) == 3)
    }

    @Test func shapesAreSeparate() {
        var levels = reached(2)
        var others = [FadeLevels.VoicingShape](repeating: shape, count: 4)
        others[0].tuning = TuningPreset.dropD.tuning
        others[1].quality = .major
        others[2].inversion = .first
        others[3].stringSet = .gBE
        #expect(others.map(levels.level(of:)) == [.first, .first, .first, .first])
        levels.add(voicing: voicing(at: 0, others[0]))
        levels.endRun()
        #expect(levels.level(of: shape) == FadeLevel(2))
    }

    @Test func theLogIsSplitIntoVoicings() {
        // A climb's are in one group. One a pause cut short starts again.
        let again = voicing(at: 0, count: 2) + voicing(at: 0) + voicing(at: 1)
        #expect(FadeLevels(log: [(group: Int, note: FadeLevels.Note)](), voicings: again.map { (group: 1, note: $0) })
            .level(of: shape) == FadeLevel(2))
        // One a stop cut short isn't finished by another group's notes.
        let cut = voicing(at: 0, count: 2).map { (group: 1, note: $0) } + voicing(at: 0).suffix(1).map { (group: 2, note: $0) }
        #expect(FadeLevels(log: [(group: Int, note: FadeLevels.Note)](), voicings: cut).level(of: shape) == .first)
    }
}

private func setup(_ levels: FadeLevels = FadeLevels(), key: Key = .major(.c), override: Int? = nil, capo: Int = 0,
                   seed: UInt64) -> DrillSetup {
    var options = DrillOptions()
    options.key = key
    options.frets = 0...22
    options.stringSets = [.dGB]
    options.inversions = [.second]
    options.triadFade = override.map(FadeLevel.init)
    var setup = DrillSetup(fretboard: Fretboard(tuning: .standard, capo: capo), options: options, seed: seed)
    setup.fadeLevels = levels
    return setup
}

/// A run whose first prompt, from 0 s, is for A minor's 2nd inversion on D-G-B: 2 2 1 (52 57 60), or an octave up.
private func asking(_ levels: FadeLevels = FadeLevels(), override: Int? = nil) -> any Drill {
    for seed in UInt64(0)..<500 {
        var drill = DrillKind.triadPlayIt.makeDrill(setup(levels, override: override, seed: seed))
        drill.handle(.start(at: s(0)))
        if drill.display?.headline == aMinorSecond.text { return drill }
    }
    fatalError("No seed asks for it")
}

private func play(_ midi: Int, at time: Double, _ drill: inout any Drill) {
    drill.handle(.played(Pitch(midi), onset: s(time), at: s(time + 0.1)))
}

/// The markers at `time`.
private func markers(_ drill: inout any Drill, at time: Double) -> [DrillDisplay.Marker] {
    drill.handle(.tick(at: s(time)))
    return drill.display?.markers ?? []
}

private func levels(logged drill: any Drill) -> [Int?] {
    drill.attempts.map { attempt in
        if case .triad(let facts) = attempt.facts { facts.fadeLevel?.number } else { nil }
    }
}

private let low = [52, 57, 60]
private let e = FretboardLocation(string: 2, fret: 2), a = FretboardLocation(string: 3, fret: 2),
            c = FretboardLocation(string: 4, fret: 1)

@Suite("Triad → play it fading")
struct TriadPlayItFadeTests {
    @Test func levelZeroShowsTheLowestVoicingsDotsAndNamesTheWholeTimeUntimed() throws {
        var drill = asking()
        let display = try #require(drill.display)
        #expect(display.markers == [
            .init(location: e, label: "E", isAnswer: false),
            .init(location: a, label: "A", isAnswer: true),
            .init(location: c, label: "C", isAnswer: false),
        ])
        #expect(display.chips.map(\.text) == ["E", "A", "C"])
        #expect(display.chips.map(\.state) == [.current, .waiting, .waiting])
        #expect(drill.timeRemaining(at: s(1)) == nil)
        #expect(markers(&drill, at: 100).map(\.opacity) == [1, 1, 1])
        #expect(drill.attempts.isEmpty && drill.phase == .waiting)
        play(52, at: 101, &drill)
        #expect(drill.attempts.map(\.responseTime) == [s(101)])
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

    @Test func fromLevelOneTheNotesButTheRootFadeOverTheFadeTimeOfTenSeconds() {
        // Level 1 fades by 90 % of 10 s.
        var drill = asking(reached(1))
        #expect(markers(&drill, at: 0).map(\.opacity) == [1, 1, 1])
        #expect(markers(&drill, at: 4.5).map(\.opacity) == [0.5, 1, 0.5])
        #expect(markers(&drill, at: 4.5).map(\.label) == ["E", "A", "C"])
        #expect(markers(&drill, at: 9).map(\.location) == [a])
        #expect(drill.display?.chips.map(\.text) == ["?", "A", "?"])
        var three = asking(reached(3))
        // Level 3 fades by 51 %: over 5.1 s.
        #expect(markers(&three, at: 2.55).map(\.opacity) == [0.5, 1, 0.5])
    }

    @Test func notesPlayedStaySolid() {
        var drill = asking(reached(1))
        play(52, at: 4.4, &drill)
        #expect(markers(&drill, at: 4.5).map(\.opacity) == [1, 1, 0.5])
        #expect(markers(&drill, at: 9.5).map(\.location) == [e, a])
    }

    @Test func atLevelSixOnlyTheRootIsShownFromTheStart() throws {
        for drill in [asking(reached(6)), asking(override: 6)] {
            let display = try #require(drill.display)
            #expect(display.markers == [.init(location: a, label: "A", isAnswer: true)])
            #expect(display.chips.map(\.text) == ["?", "A", "?"])
        }
    }

    @Test func fromLevelOneItIsTimed() {
        for level in [1, 6] {
            var timed = asking(reached(level))
            #expect(timed.timeRemaining(at: s(1)) == s(9))
            timed.handle(.tick(at: s(10.3)))
            #expect(timed.phase == .timedOut)
        }
    }

    @Test func aTimedOutVoicingIsShownWhole() {
        var drill = asking(reached(6))
        #expect(markers(&drill, at: 10.3).map(\.opacity) == [1, 1, 1])
    }

    @Test func aHintShowsItWhileHeldAndIsLogged() {
        var drill = asking(reached(6))
        play(52, at: 1, &drill)
        drill.handle(.hint(isShown: true, at: s(2)))
        #expect(drill.display?.markers.map(\.label) == ["E", "A", "C"])
        #expect(drill.display?.markers.map(\.opacity) == [1, 1, 1])
        // Still timed.
        #expect(drill.timeRemaining(at: s(2)) == s(9))
        drill.handle(.hint(isShown: false, at: s(3)))
        #expect(drill.display?.markers.map(\.label) == ["E", "A"])
        play(57, at: 4, &drill)
        let hinted = drill.attempts.map { if case .triad(let facts) = $0.facts { facts.hinted } else { false } }
        #expect(hinted == [false, true])
        play(60, at: 5, &drill)
        #expect(drill.fadeLevels?.level(of: shape) == .last)
        #expect(drill.fadeLevels?.levelAfterRun(of: shape) == FadeLevel(5))
    }

    @Test func pausingEndsAHint() {
        var drill = asking(override: 6)
        drill.handle(.hint(isShown: true, at: s(1)))
        drill.handle(.pause(at: s(2)))
        drill.handle(.resume(at: s(3)))
        #expect(drill.display?.markers.map(\.isAnswer) == [true])
    }

    @Test func aCleanOneMovesItUpAndIsLoggedAtItsLevel() {
        var drill = asking(reached(2))
        for (index, midi) in low.enumerated() { play(midi, at: 1 + Double(index), &drill) }
        #expect(drill.fadeLevels?.level(of: shape) == FadeLevel(2))
        #expect(drill.fadeLevels?.levelAfterRun(of: shape) == FadeLevel(3))
        #expect(levels(logged: drill) == [2, 2, 2])
        drill = asking()
        for (index, midi) in low.enumerated() { play(midi, at: 1 + Double(index), &drill) }
        #expect(levels(logged: drill) == [0, 0, 0])
        let notes = drill.attemptsToLog.compactMap { attempt in
            FadeLevels.VoicingNote(attempt, in: .standard).map { (group: attempt.group?.number ?? -1, note: $0) }
        }
        #expect(FadeLevels(log: [(group: Int, note: FadeLevels.Note)](), voicings: notes).level(of: shape) == FadeLevel(1))
    }

    @Test func aSkippedOneLeavesIt() {
        var drill = asking(reached(2))
        play(52, at: 1, &drill)
        drill.handle(.skip(at: s(2)))
        #expect(drill.fadeLevels?.level(of: shape) == FadeLevel(2))
    }

    @Test func anOverrideDoesntMoveIt() {
        var drill = asking(override: 6)
        for (index, midi) in low.enumerated() { play(midi, at: 1 + Double(index), &drill) }
        #expect(drill.fadeLevels?.level(of: shape) == .first)
        #expect(levels(logged: drill) == [6, 6, 6])
    }

    @Test func resumingTakesUpWhatWasReachedMeanwhile() {
        var drill = asking()
        drill.handle(.pause(at: s(1)))
        var all = FadeLevels()
        for quality in Triad.Quality.allCases {
            all.add(voicing: voicing(at: 0, .init(tuning: .standard, quality: quality, inversion: .second, stringSet: .dGB)))
        }
        all.endRun()
        drill.handle(.fadeLevels(all))
        drill.handle(.resume(at: s(2)))
        #expect(markers(&drill, at: 6.5).map(\.opacity) == [0.5, 1, 0.5])
    }

    @Test func aMinorAndDMinorShareIt() {
        // A chord of another root, in the same shape.
        for seed in UInt64(0)..<500 {
            var drill = DrillKind.triadPlayIt.makeDrill(setup(reached(6), seed: seed))
            drill.handle(.start(at: s(0)))
            guard drill.display?.headline == "D minor · 2nd inversion" else { continue }
            #expect(drill.display?.markers.map(\.label) == ["D"])
            return
        }
        Issue.record("No seed asks for D minor")
    }
}

@Suite("Inversions fading")
struct InversionsFadeTests {
    /// A minor on D-G-B up to fret 12: 2nd inversion, root position, 1st inversion, and back.
    private func climbing(_ levels: FadeLevels = FadeLevels()) -> any Drill {
        for seed in UInt64(0)..<500 {
            var options = DrillOptions()
            options.stringSets = [.dGB]
            var setup = DrillSetup(fretboard: Fretboard(tuning: .standard), options: options, seed: seed)
            setup.fadeLevels = levels
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

    @Test func theWayBackStaysAtTheLevelFromBeforeTheRun() throws {
        var drill = climbing()
        #expect(drill.display?.chips.map(\.text) == ["E", "A", "C"])
        #expect(drill.timeRemaining(at: s(1)) == nil)
        play(low, from: 1, &drill)
        play(root, from: 6, &drill)
        #expect(drill.display?.markers.map(\.opacity) == [1, 1, 1])
        play(first, from: 11, &drill)
        // Root position again, still at level 0 this run, though the way up was clean.
        let start = try #require(drill.promptStart) / .seconds(1)
        #expect(drill.fadeLevels?.level(of: shape) == .first)
        #expect(drill.fadeLevels?.levelAfterRun(of: shape) == FadeLevel(1))
        #expect(markers(&drill, at: start + 4.5).map(\.opacity) == [1, 1, 1])
    }

    @Test func aVoicingResumedStartsAfresh() {
        var drill = climbing()
        drill.handle(.played(Pitch(50), onset: s(1), at: s(1.1)))
        drill.handle(.played(Pitch(52), onset: s(2), at: s(2.1)))
        drill.handle(.pause(at: s(3)))
        drill.handle(.resume(at: s(4)))
        play(low, from: 5, &drill)
        #expect(drill.fadeLevels?.levelAfterRun(of: shape) == FadeLevel(1))
        let notes = drill.attemptsToLog.compactMap { attempt in
            FadeLevels.VoicingNote(attempt, in: .standard).map { (group: attempt.group?.number ?? -1, note: $0) }
        }
        #expect(FadeLevels(log: [(group: Int, note: FadeLevels.Note)](), voicings: notes).level(of: shape) == FadeLevel(1))
    }
}

@Suite("Triads fading in a session")
struct SessionTriadFadeTests {
    @Test func theBlocksCarryItOnAndTakeHints() {
        let block = SessionBlock(kind: .triadPlayIt, length: s(180))
        var levels = FadeLevels()
        for quality in Triad.Quality.allCases {
            for number in 0..<6 {
                levels.add(voicing: voicing(at: number, .init(tuning: .standard, quality: quality, inversion: .second,
                                                              stringSet: .dGB)))
                levels.endRun()
            }
        }
        var player = SessionPlayer(blocks: [block, block], setup: setup(levels, seed: 1))
        player.handle(.start(at: s(0)))
        player.handle(.next(at: s(0)))
        #expect(player.display?.markers.count == 1)
        player.handle(.hint(isShown: true, at: s(1)))
        #expect(player.display?.markers.count == 3)
        player.handle(.next(at: s(2)))
        player.handle(.next(at: s(3)))
        #expect(player.display?.markers.count == 1)
    }
}
