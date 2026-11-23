import Testing
import TheoryCore
import PracticeCore

/// A drill made up for these tests: typed answers, sounds and its own timing. Prompts are string 6's frets in order.
/// With a capo at fret 1 it runs like a sweep instead: continuous, resuming on the same prompt.
struct ToyRules: DrillRules {
    static let kind = DrillKind(id: "toy", title: "Toy", instructions: "", symbol: "star", rules: ToyRules.self)
    static let timeout: Duration = .seconds(15)

    let setup: DrillSetup
    var fret = -1
    var continuous: Bool { setup.fretboard.capo == 1 }

    init(setup: DrillSetup) { self.setup = setup }

    mutating func nextPrompt(after previous: NotePrompt?) -> NotePrompt? {
        fret += 1
        return setup.prompt(at: FretboardLocation(string: 0, fret: fret))
    }

    func judge(_ answer: DrillAnswer, for prompt: NotePrompt) -> DrillJudgement {
        switch answer {
        case .named(let name): name.pitchClass == prompt.pitchClass ? .right(prompt.target!) : .wrong(.name(name))
        case .played(let pitch): pitch.pitchClass == prompt.pitchClass ? .right(prompt.target!) : .ignored
        }
    }

    func correctLocations(for prompt: NotePrompt) -> [FretboardLocation] { [prompt.target!] }
    func sounds(for prompt: NotePrompt) -> [DrillTone] { [DrillTone(pitch: Pitch(40), duration: .milliseconds(600))] }
    func timerDelay(for prompt: NotePrompt) -> Duration { continuous ? .zero : .milliseconds(600) }
    mutating func repeated() -> DrillRepeat { continuous ? .newPrompt : .replaySounds }
    func transition(after attempt: Attempt) -> DrillTransition { continuous ? .continuous : .standard(after: attempt) }
    var resumeRule: DrillResumeRule { continuous ? .samePrompt(keepingWrongAnswers: true) : .newPrompt }
}

private func toy(continuous: Bool = false) -> PromptDrill<ToyRules> {
    var drill = PromptDrill<ToyRules>(fretboard: Fretboard(tuning: .standard, capo: continuous ? 1 : 0), options: .init(), seed: 1)
    drill.handle(.start(at: s(0)))
    return drill
}

@Suite("Shared drill interface")
struct SharedDrillTests {
    @Test func aTypedNameCanBeRightOrWrong() {
        var drill = toy()
        drill.handle(.typed(.gSharp, at: s(2)))
        #expect(drill.phase == .wrong(PitchClass(8)))
        drill.handle(.typed(.e, at: s(3.6)))
        #expect(drill.phase == .correct(FretboardLocation(string: 0, fret: 0)))
        #expect(drill.attempts[0].responseTime == s(3))
        #expect(drill.attempts[0].wrongAnswers == [.name(.gSharp)])
        #expect(drill.attempts[0].summaryLine(in: .standard) == "E on string 6 (E) — 3.00 s · typed G♯ first")
    }

    @Test func aTypedNameAfterTheTimeoutDoesNotCount() {
        var drill = toy()
        drill.handle(.typed(.e, at: s(15.65)))
        #expect(drill.phase == .timedOut)
    }

    @Test func notePlayItIgnoresTypedNames() {
        var drill = lowEDrill()
        drill.handle(.typed(.e, at: s(1)))
        #expect(drill.phase == .waiting)
    }

    @Test func anIgnoredAnswerChangesNothing() {
        var drill = toy()
        drill.handle(.played(Pitch(43), onset: s(1), at: s(1.1)))
        #expect(drill.phase == .waiting)
    }

    @Test func eachDrillHasItsOwnTimeoutAndTimerDelay() {
        var drill = toy()
        #expect(drill.timeLimit == s(15))
        #expect(drill.promptStart == s(0.6))
        #expect(drill.timeRemaining(at: s(0)) == s(15))
        drill.handle(.tick(at: s(15.79)))
        #expect(drill.phase == .waiting)
        drill.handle(.tick(at: s(15.8)))
        #expect(drill.phase == .timedOut)
    }

    @Test func aPromptRequestsItsSoundsOnceAndRepeatRequestsThemAgainWithoutResettingTheTimer() {
        var drill = toy()
        let tone = DrillTone(pitch: Pitch(40), duration: .milliseconds(600))
        #expect(drill.takeSounds() == [DrillSoundRequest(tones: [tone], at: s(0))])
        #expect(drill.takeSounds() == [])
        drill.handle(.repeat(at: s(4)))
        #expect(drill.takeSounds() == [DrillSoundRequest(tones: [tone], at: s(4))])
        #expect(drill.promptStart == s(0.6))
        #expect(drill.prompt?.target?.fret == 0)
    }

    @Test func repeatDoesNothingWhileTheAnswerIsShownOrPausedOrWhereADrillHasNone() {
        var drill = toy()
        _ = drill.takeSounds()
        drill.handle(.typed(.e, at: s(1)))
        drill.handle(.repeat(at: s(1.1)))
        #expect(drill.takeSounds() == [])
        drill.handle(.pause(at: s(1.2)))
        drill.handle(.repeat(at: s(1.3)))
        #expect(drill.takeSounds() == [])

        var notePlayIt = lowEDrill()
        notePlayIt.handle(.repeat(at: s(1)))
        #expect(notePlayIt.promptStart == s(0))
        #expect(notePlayIt.takeSounds() == [])
    }

    @Test func pauseDropsSoundsNotYetTaken() {
        var drill = toy()
        drill.handle(.pause(at: s(0)))
        #expect(drill.takeSounds() == [])
    }

    @Test func repeatCanGiveANewPromptWithNoAttempt() {
        var drill = toy(continuous: true)
        drill.handle(.repeat(at: s(2)))
        #expect(drill.prompt?.target?.fret == 1)
        #expect(drill.promptStart == s(2))
        #expect(drill.attempts.isEmpty)
    }

    @Test func aContinuousDrillTimesFromThePreviousPromptBeingDealtWith() {
        var drill = toy(continuous: true)
        // E at 1.0 (detected 1.1), F at 1.3: no pause swallows it.
        drill.handle(.played(Pitch(40), onset: s(1), at: s(1.1)))
        #expect(drill.phase == .waiting)
        #expect(drill.promptStart == s(1))
        drill.handle(.played(Pitch(41), onset: s(1.3), at: s(1.4)))
        #expect(drill.attempts.map(\.responseTime) == [s(1), s(0.3)])
        // F♯ times out at 16.3, and G played just after counts for the next location.
        drill.handle(.played(Pitch(43), onset: s(16.35), at: s(16.45)))
        #expect(drill.attempts.map(\.outcome) == [.answered, .answered, .timedOut, .answered])
        #expect(drill.attempts.last?.responseTime == s(0.05))
    }

    @Test func aContinuousDrillResumesOnTheSamePromptWithItsTimerRestarted() {
        var drill = toy(continuous: true)
        drill.handle(.typed(.g, at: s(1)))
        drill.handle(.pause(at: s(2)))
        #expect(drill.prompt == nil)
        drill.handle(.resume(at: s(10)))
        #expect(drill.phase == .wrong(PitchClass(7)))
        #expect(drill.prompt?.target?.fret == 0)
        #expect(drill.promptStart == s(10))
        drill.handle(.typed(.e, at: s(11)))
        #expect(drill.attempts.first?.responseTime == s(1))
        #expect(drill.attempts.first?.wrongAnswers == [.name(.g)])
    }
}

@Suite("Drill kinds")
struct DrillKindTests {
    @Test func everyKindMakesARunnableDrillOfItsKind() {
        #expect(!DrillKind.all.isEmpty)
        #expect(Set(DrillKind.all.map(\.id)).count == DrillKind.all.count)
        for kind in DrillKind.all {
            var drill = kind.makeDrill(DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1))
            #expect(drill.kind == kind)
            #expect(drill.nothingToPromptReason == nil)
            drill.handle(.start(at: s(0)))
            #expect(drill.phase == .waiting)
            #expect(drill.display != nil)
        }
    }

    @Test func notePlayItIsListed() {
        #expect(DrillKind.all.contains(.notePlayIt))
        #expect(DrillKind.notePlayIt.title == "Note → play it")
    }

    @Test func orderAppliesOnlyToDrillsThatOfferIt() {
        // The Drill screen keeps one set of options for every drill.
        var options = DrillOptions()
        options.order = .inOrder
        let setup = DrillSetup(fretboard: Fretboard(tuning: .standard), options: options, seed: 1)
        #expect(DrillKind.notePlayIt.makeDrill(setup).isCheckRun)
        #expect(!ToyRules.kind.makeDrill(setup).isCheckRun)
    }
}

@Suite("Spelling and weighting")
struct SpellingAndWeightingTests {
    func prompts(_ weighting: NoteWeighting?, notes: DrillOptions.Notes = .all, count: Int = 2000) -> [NotePrompt] {
        var options = DrillOptions()
        options.notes = notes
        let setup = DrillSetup(fretboard: Fretboard(tuning: .standard), options: options,
                               key: .major(.bFlat), weighting: weighting, seed: 5)
        var run = NotePlayItDrill(setup: setup)
        return promptsShown(by: &run, count: count)
    }

    /// B♭ C D E♭ F G A.
    let bFlatMajor = Set([10, 0, 2, 3, 5, 7, 9].map { PitchClass($0) })

    @Test func promptsAreSpelledInTheKey() {
        let names = prompts(nil, count: 300).map(\.noteName)
        #expect(Set(names).isSuperset(of: ["B♭", "E♭"]))
        #expect(!names.contains("A♯"))
        // String labels stay sharp.
        #expect(NotePrompt(name: .bFlat, string: 3).text(in: TuningPreset.eFlatStandard.tuning) == "B♭ on string 3 (F♯)")
    }

    @Test func thePreferredNotesGetTheirShare() {
        let weighting = NoteWeighting(preferred: bFlatMajor, share: 0.7)
        let preferred = prompts(weighting).filter { bFlatMajor.contains($0.pitchClass) }.count
        #expect((1320...1480).contains(preferred))
        // Among naturals, E and B are outside.
        let others = prompts(weighting, notes: .naturals).filter { ["E", "B"].contains($0.noteName) }.count
        #expect((520...680).contains(others))
    }

    @Test func aWeightingThatPrefersNothingInRangeStillPrompts() {
        #expect(prompts(NoteWeighting(preferred: [], share: 0.7), count: 50).count == 50)
    }
}

@Suite("Drill display")
struct DrillDisplayTests {
    @Test func waitingWrongRightAndTimedOut() throws {
        var drill = lowEDrill()
        var display = try #require(drill.display)
        #expect(display.headline == "E")
        #expect(display.subline == "on string 6 (E) · fret 0")
        #expect(display.feedback == "Listening…")
        #expect(display.result == .waiting)
        #expect(display.highlightedString == 0)
        #expect(display.markers.isEmpty)

        drill.handle(.played(Pitch(43), onset: s(1), at: s(1.1)))
        display = try #require(drill.display)
        #expect(display.feedback == "You played G")
        #expect(display.result == .wrong)

        drill.handle(.played(Pitch(40), onset: s(2), at: s(2.1)))
        display = try #require(drill.display)
        #expect(display.feedback == "Fret 0 · 2.00 s")
        #expect(display.result == .right)
        #expect(display.markers == [.init(location: FretboardLocation(string: 0, fret: 0), label: "E", isAnswer: true)])

        drill.handle(.tick(at: s(2.5)))
        drill.handle(.tick(at: s(12.7)))
        display = try #require(drill.display)
        #expect(display.feedback == "Time's up — here it is")
        #expect(display.result == .timedOut)
        #expect(display.markers == [.init(location: FretboardLocation(string: 0, fret: 1), label: "F", isAnswer: false)])
    }

    @Test func nothingWhenIdle() {
        #expect(drill().display == nil)
    }
}
