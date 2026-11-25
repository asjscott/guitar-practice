import Testing
import TheoryCore
import PracticeCore

private func at(_ string: Int, _ fret: Int) -> FretboardLocation { FretboardLocation(string: string, fret: fret) }

private func setup(_ preset: TuningPreset = .standard, capo: Int = 0, seed: UInt64 = 1,
                   _ change: (inout DrillOptions) -> Void = { _ in }) -> DrillSetup {
    var options = DrillOptions()
    options.triadFade = .hidden
    options.frets = 0...22
    change(&options)
    return DrillSetup(fretboard: Fretboard(tuning: preset.tuning, capo: capo), options: options, seed: seed)
}

/// A run whose first prompt is for one chord, in one inversion on one string set: the first seed that gives it.
private func asking(_ triad: Triad, _ inversion: Triad.Inversion, on set: StringSet, in preset: TuningPreset = .standard,
                    frets: ClosedRange<Int> = 0...22) -> any Drill {
    for seed in UInt64(0)..<500 {
        var drill = DrillKind.triadPlayIt.makeDrill(setup(preset, seed: seed) {
            $0.frets = frets
            $0.stringSets = [set]
            $0.inversions = [inversion]
        })
        drill.handle(.start(at: s(0)))
        if drill.display?.headline == TriadFacts(triad: triad, inversion: inversion, stringSet: set).text { return drill }
    }
    fatalError("No seed asks for \(triad)")
}

/// On D-G-B at frets 2 2 1 (MIDI 52 57 60) or an octave up, at 14 14 13 (64 69 72).
private func aMinorSecond() -> any Drill { asking(Triad(.minor, root: .a), .second, on: .dGB) }

/// Plays a pitch, heard 0.1 s after its onset.
private func play(_ midi: Int, at time: Double, _ drill: inout any Drill) {
    drill.handle(.played(Pitch(midi), onset: s(time), at: s(time + 0.1)))
}

@Suite("Triad → play it")
struct TriadPlayItTests {
    @Test func itIsATriadsDrill() {
        #expect(DrillKind.all.contains(.triadPlayIt))
        #expect(DrillKind.triadPlayIt.id == "triadPlayIt")
        #expect(DrillKind.triadPlayIt.module == .triads)
        #expect(DrillKind.triadPlayIt.repeatTitle == nil)
    }

    @Test func waitingNamesTheChordAndLightsTheSetButNoNotes() throws {
        let display = try #require(aMinorSecond().display)
        #expect(display.headline == "A minor · 2nd inversion")
        #expect(display.subline == "D-G-B")
        #expect(display.highlightedStrings == [2, 3, 4])
        #expect(display.markers.isEmpty)
        #expect(display.chips.map(\.title) == ["4", "3", "2"])
        #expect(display.chips.map(\.spokenTitle) == ["string 4 (D)", "string 3 (G)", "string 2 (B)"])
        #expect(display.chips.map(\.text) == ["?", "?", "?"])
        #expect(display.chips.map(\.state) == [.current, .waiting, .waiting])
        #expect(display.feedback == "Listening…")
    }

    @Test(arguments: [[52, 57, 60], [64, 69, 72]])
    func eitherOctaveIsRightLowToHigh(_ pitches: [Int]) {
        var drill = aMinorSecond()
        play(pitches[0], at: 2, &drill)
        play(pitches[1], at: 2.5, &drill)
        #expect(drill.phase == .waiting)
        play(pitches[2], at: 3.25, &drill)
        #expect(drill.attempts.map(\.outcome) == [.answered, .answered, .answered])
        #expect(drill.attempts.map(\.responseTime) == [s(2), s(0.5), s(0.75)])
        #expect(drill.attempts.allSatisfy { $0.firstRight })
        #expect(drill.attempts.map(\.prompt.noteName) == ["E", "A", "C"])
        let heard = drill.attempts.compactMap(\.location).map { drill.fretboard.pitch(at: $0).midi }
        #expect(heard == pitches)
        #expect(drill.display?.feedback == "3.25 s")
        #expect(drill.display?.markers.count == 3)
        #expect(drill.display?.result == .right)
    }

    @Test func notesOfTheOtherStringsOrOrderAreWrong() {
        var drill = aMinorSecond()
        // The E on the open low string, A before E, then the E itself.
        play(40, at: 1, &drill)
        #expect(drill.phase == .wrong(PitchClass(4)))
        #expect(drill.display?.feedback == "You played E, in another octave")
        play(57, at: 2, &drill)
        #expect(drill.display?.feedback == "You played A")
        #expect(drill.display?.result == .wrong)
        play(52, at: 3, &drill)
        #expect(drill.attempts.count == 1)
        #expect(drill.attempts[0].wrongAnswers == [.pitch(Pitch(40)), .pitch(Pitch(57))])
        #expect(!drill.attempts[0].firstRight)
    }

    @Test func theFirstNotePicksTheVoicingTheOthersBelongTo() {
        var drill = aMinorSecond()
        play(64, at: 1, &drill)
        play(57, at: 2, &drill)
        #expect(drill.phase == .wrong(PitchClass(9)))
        // What was played stays up.
        #expect(drill.display?.chips.map(\.text) == ["E", "?", "?"])
        play(69, at: 3, &drill)
        #expect(drill.attempts.map(\.wrongAnswers) == [[], [.pitch(Pitch(57))]])
        #expect(drill.attempts[1].responseTime == s(2))
    }

    @Test func onlyTheLastNotePlayedIsOnTheNeckUntilTheVoicingIsDone() throws {
        var drill = aMinorSecond()
        play(52, at: 1, &drill)
        play(57, at: 2, &drill)
        let display = try #require(drill.display)
        #expect(display.markers == [.init(location: at(3, 2), label: "A", isAnswer: true, isLastPlayed: true)])
        #expect(display.chips.map(\.text) == ["E", "A", "?"])
        #expect(display.chips.map(\.state) == [.found, .found, .current])
        #expect(display.highlightedStrings == [2, 3, 4])
        play(60, at: 3, &drill)
        #expect(drill.display?.markers == [
            .init(location: at(2, 2), label: "E", isAnswer: false),
            .init(location: at(3, 2), label: "A", isAnswer: true),
            .init(location: at(4, 1), label: "C", isAnswer: false, isLastPlayed: true),
        ])
    }

    @Test func aRightVoicingGivesWayToAnotherPrompt() {
        var drill = aMinorSecond()
        for (index, pitch) in [52, 57, 60].enumerated() { play(pitch, at: Double(index + 1), &drill) }
        drill.handle(.tick(at: s(3.49)))
        #expect(drill.display?.result == .right)
        drill.handle(.tick(at: s(3.5)))
        #expect(drill.phase == .waiting)
        #expect(drill.promptStart == s(3.5))
        #expect(drill.display?.headline != "A minor · 2nd inversion")
    }

    @Test func eachNoteIsAnAttemptGroupedWithItsChord() {
        var drill = aMinorSecond()
        for (index, pitch) in [52, 57, 60].enumerated() { play(pitch, at: Double(index + 1), &drill) }
        drill.handle(.tick(at: s(4)))
        drill.handle(.skip(at: s(5)))
        var facts = TriadFacts(triad: Triad(.minor, root: .a), inversion: .second, stringSet: .dGB)
        facts.fadeStage = .hidden
        #expect(drill.attempts.prefix(3).map(\.facts) == Array(repeating: .triad(facts), count: 3))
        #expect(drill.attempts.map { $0.group?.place } == [0, 1, 2, 0])
        #expect(drill.attempts.allSatisfy { $0.group?.size == 3 })
        let groups = drill.attempts.compactMap { $0.group?.number }
        #expect(groups[0] == groups[1] && groups[1] == groups[2] && groups[2] != groups[3])
        #expect(drill.attemptsToLog.count == 4)
        // The skipped prompt isn't counted.
        #expect(drill.stats.prompts == 1)
        #expect(drill.stats.skips == 1)
    }

    @Test func tenSecondsOnTheFirstNoteRevealsTheLowestVoicing() throws {
        var drill = aMinorSecond()
        #expect(drill.timeLimit == s(10))
        drill.handle(.tick(at: s(10.1)))
        #expect(drill.phase == .waiting)
        drill.handle(.tick(at: s(10.2)))
        let display = try #require(drill.display)
        #expect(display.result == .timedOut)
        #expect(display.markers.map(\.location) == [at(2, 2), at(3, 2), at(4, 1)])
        #expect(display.markers.map(\.label) == ["E", "A", "C"])
        #expect(display.chips.map(\.text) == ["E", "A", "C"])
        #expect(display.chips.map(\.state) == [.timedOut, .timedOut, .timedOut])
        #expect(display.feedback == "Time's up — here it is")
        #expect(drill.attempts.map(\.outcome) == [.timedOut])
        drill.handle(.tick(at: s(12)))
        #expect(drill.attempts.count == 1)
        #expect(drill.phase == .waiting)
        #expect(drill.display?.headline != "A minor · 2nd inversion")
    }

    @Test func laterNotesHaveTenSecondsEachAndRevealTheVoicingPicked() {
        var drill = aMinorSecond()
        play(64, at: 9, &drill)
        #expect(drill.timeRemaining(at: s(10)) == s(9))
        drill.handle(.tick(at: s(19.2)))
        #expect(drill.display?.markers.map(\.location) == [at(2, 14), at(3, 14), at(4, 13)])
        #expect(drill.display?.chips.map(\.state) == [.found, .timedOut, .timedOut])
        #expect(drill.attempts.map(\.outcome) == [.answered, .timedOut])
    }

    @Test func skipDropsTheRestOfThePrompt() {
        var drill = aMinorSecond()
        play(52, at: 1, &drill)
        drill.handle(.skip(at: s(2)))
        #expect(drill.attempts.map(\.outcome) == [.answered, .skipped])
        #expect(drill.prompt?.string == 2)
        #expect(drill.display?.headline != "A minor · 2nd inversion")
        #expect(drill.display?.chips.map(\.text) == ["?", "?", "?"])
    }

    @Test func repeatDoesNothing() {
        var drill = aMinorSecond()
        play(52, at: 1, &drill)
        let before = drill.display
        drill.handle(.repeat(at: s(2)))
        #expect(drill.display == before)
        #expect(drill.promptStart == s(1))
    }

    @Test func resumeGivesANewPromptAndKeepsTheNotesDealtWith() {
        var drill = aMinorSecond()
        play(52, at: 1, &drill)
        drill.handle(.pause(at: s(2)))
        #expect(drill.display == nil)
        drill.handle(.resume(at: s(5)))
        #expect(drill.prompt?.string == 2)
        #expect(drill.promptStart == s(5))
        #expect(drill.display?.headline != "A minor · 2nd inversion")
        #expect(drill.attempts.count == 1)
    }

    @Test func restartingForgetsTheOldPrompt() {
        var drill = aMinorSecond()
        play(52, at: 1, &drill)
        drill.handle(.stop(at: s(2)))
        drill.handle(.start(at: s(3)))
        #expect(drill.prompt?.string == 2)
        #expect(drill.attempts.isEmpty)
    }

    @Test func summaryLinesNameTheChord() {
        var drill = aMinorSecond()
        play(53, at: 0.5, &drill)
        play(52, at: 1.25, &drill)
        #expect(drill.attempts[0].summaryLine(in: .standard, key: drill.setup.key)
            == "A minor · 2nd inversion: E on string 4 (D) — 1.25 s · played F first")
    }
}

@Suite("Triad prompts")
struct TriadPromptTests {
    /// The prompts of a run, each skipped.
    private func prompts(_ setup: DrillSetup, count: Int) -> [TriadFacts] {
        var drill = DrillKind.triadPlayIt.makeDrill(setup)
        drill.handle(.start(at: s(0)))
        for index in 0..<count { drill.handle(.skip(at: s(Double(index + 1)))) }
        return drill.attempts.compactMap { if case .triad(let facts) = $0.facts { facts } else { nil } }
    }

    @Test(arguments: [TuningPreset.standard, .dropD, .dadgad, .openG], [0, 5])
    func everyPromptHasAVoicingInRangeAndDiffersFromTheLast(_ preset: TuningPreset, _ capo: Int) {
        let setup = setup(preset, capo: capo) { $0.frets = 0...12 }
        let asked = prompts(setup, count: 400)
        #expect(asked.count == 400)
        for prompt in asked {
            #expect(!setup.fretboard.voicings(of: prompt.triad, inversion: prompt.inversion, on: prompt.stringSet, frets: 0...12).isEmpty)
        }
        #expect(zip(asked, asked.dropFirst()).allSatisfy { $0 != $1 })
        #expect(Set(asked.map(\.inversion)).count == 3)
        #expect(Set(asked.map(\.triad.name)) == ["C major", "D minor", "E minor", "F major", "G major", "A minor"])
    }

    @Test func theOptionsNarrowThem() {
        let asked = prompts(setup {
            $0.key = .minor(.dSharp)
            $0.stringSets = [.aDG, .gBE]
            $0.inversions = [.first]
        }, count: 200)
        #expect(Set(asked.map(\.stringSet)) == [.aDG, .gBE])
        #expect(Set(asked.map(\.inversion)) == [.first])
        #expect(Set(asked.map(\.triad.name)) == ["D♯ minor", "F♯ major", "G♯ minor", "A♯ minor", "B major", "C♯ major"])
    }

    @Test func aSessionsKeyComesBeforeTheOptions() {
        var setup = setup()
        setup.key = .major(.bFlat)
        #expect(Set(prompts(setup, count: 100).map(\.triad.name)) == ["B♭ major", "C minor", "D minor", "E♭ major", "F major", "G minor"])
        #expect(DrillKind.triadPlayIt.makeDrill(setup).setup.key == .major(.bFlat))
    }

    @Test func naturalsAndIncludedStringsDoNotApply() {
        let asked = prompts(setup {
            $0.key = .major(.fSharp)
            $0.notes = .naturals
            $0.strings = [0]
        }, count: 100)
        #expect(Set(asked.map(\.stringSet)).count == 4)
    }

    @Test func noVoicingInRangeIsAReasonNotToStart() {
        // Only fret 12 can be played.
        let none = DrillKind.triadPlayIt.makeDrill(setup(capo: 12) {
            $0.frets = 0...12
            $0.stringSets = [.eAD]
            $0.inversions = [.root]
        })
        #expect(none.nothingToPromptReason == "No voicing of the key’s chords fits these frets, string sets and inversions.")
        #expect(DrillKind.triadPlayIt.makeDrill(setup(capo: 12) { $0.frets = 0...12 }).nothingToPromptReason == nil)
    }

    /// E minor, 1st inversion (G B E) on D A D: frets 5 2 2, or 17 14 14.
    @Test(arguments: [[43, 47, 52], [55, 59, 64]])
    func dropD(_ pitches: [Int]) {
        var drill = asking(Triad(.minor, root: .e), .first, on: .eAD, in: .dropD)
        for (index, pitch) in pitches.enumerated() { play(pitch, at: Double(index + 1), &drill) }
        #expect(drill.attempts.map(\.firstRight) == [true, true, true])
        #expect(drill.attempts.map { $0.location?.fret } == (pitches[0] == 43 ? [5, 2, 2] : [17, 14, 14]))
    }

    /// G major in root position on G B D: the open strings, or fret 12.
    @Test(arguments: [[55, 59, 62], [67, 71, 74]])
    func openG(_ pitches: [Int]) {
        var drill = asking(Triad(.major, root: .g), .root, on: .gBE, in: .openG)
        for (index, pitch) in pitches.enumerated() { play(pitch, at: Double(index + 1), &drill) }
        #expect(drill.attempts.map(\.firstRight) == [true, true, true])
        #expect(drill.display?.subline == "G-B-E")
        #expect(drill.display?.chips.map(\.spokenTitle) == ["string 3 (G)", "string 2 (B)", "string 1 (D)"])
    }

    @Test func aVoicingPastTheRangeIsWrong() {
        var drill = asking(Triad(.major, root: .g), .root, on: .gBE, in: .openG, frets: 0...11)
        play(67, at: 1, &drill)
        #expect(drill.phase == .wrong(PitchClass(7)))
    }
}
