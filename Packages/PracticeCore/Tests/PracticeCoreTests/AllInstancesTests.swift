import Testing
import TheoryCore
import PracticeCore

private func at(_ string: Int, _ fret: Int) -> FretboardLocation { FretboardLocation(string: string, fret: fret) }

/// A run whose first sweep is of one note: the first seed that gives it.
private func sweeping(_ note: NoteName, on fretboard: Fretboard = Fretboard(tuning: .standard),
                      _ change: (inout DrillSetup) -> Void = { _ in }) -> any Drill {
    for seed in UInt64(0)..<500 {
        var setup = DrillSetup(fretboard: fretboard, seed: seed)
        setup.options.notes = note.pitchClass.isNatural ? .naturals : .all
        change(&setup)
        var drill = DrillKind.allInstances.makeDrill(setup)
        drill.handle(.start(at: s(0)))
        if drill.prompt?.pitchClass == note.pitchClass { return drill }
    }
    fatalError("No seed sweeps \(note)")
}

/// Plays each prompt's own pitch, one second apart, until the sweep ends; returns its locations in order.
@discardableResult
private func finishSweep(_ drill: inout any Drill, from start: Double = 0) -> [FretboardLocation] {
    var found: [FretboardLocation] = []
    while drill.phase == .waiting, let target = drill.prompt?.target, found.count < 100 {
        found.append(target)
        let time = start + Double(found.count)
        drill.handle(.played(drill.fretboard.pitch(at: target), onset: s(time), at: s(time + 0.1)))
    }
    return found
}

/// Standard tuning, frets 0–12.
private let everyC = [at(0, 8), at(1, 3), at(2, 10), at(3, 5), at(4, 1), at(5, 8)]

@Suite("All instances: the sweep")
struct SweepOrderTests {
    @Test func everyCFromString6LowestFretFirst() {
        var drill = sweeping(.c)
        #expect(finishSweep(&drill) == everyC)
    }

    @Test func openStringAndFret12BothCount() {
        var drill = sweeping(.e)
        #expect(finishSweep(&drill) == [at(0, 0), at(0, 12), at(1, 7), at(2, 2), at(3, 9), at(4, 5), at(5, 0), at(5, 12)])
    }

    @Test func dropD() {
        var drill = sweeping(.d, on: Fretboard(tuning: TuningPreset.dropD.tuning))
        #expect(finishSweep(&drill) == [at(0, 0), at(0, 12), at(1, 5), at(2, 0), at(2, 12), at(3, 7), at(4, 3), at(5, 10)])
    }

    @Test func aCapoLeavesOutTheFretsBelowIt() {
        var drill = sweeping(.c, on: Fretboard(tuning: .standard, capo: 5))
        #expect(finishSweep(&drill) == [at(0, 8), at(2, 10), at(3, 5), at(5, 8)])
    }

    @Test func capo12OnTheWholeNeck() {
        var drill = sweeping(.c, on: Fretboard(tuning: .standard, capo: 12)) { $0.options.frets = 0...22 }
        #expect(finishSweep(&drill) == [at(0, 20), at(1, 15), at(2, 22), at(3, 17), at(4, 13), at(5, 20)])
    }

    @Test func includedStringsOnly() {
        var drill = sweeping(.c) { $0.options.strings = [1, 4] }
        #expect(finishSweep(&drill) == [at(1, 3), at(4, 1)])
    }

    @Test(arguments: [TuningPreset.dropD, .dadgad, .openG], [0, 3, 12])
    func everyLocationOnceInOrder(preset: TuningPreset, capo: Int) {
        let fretboard = Fretboard(tuning: preset.tuning, capo: capo)
        var options = DrillOptions()
        options.notes = .all
        options.frets = 0...22
        var drill = DrillKind.allInstances.makeDrill(DrillSetup(fretboard: fretboard, options: options, seed: 3))
        drill.handle(.start(at: s(0)))
        let note = drill.prompt!.pitchClass
        #expect(finishSweep(&drill) == fretboard.locations(of: note))
    }

    @Test func spelledInTheKey() {
        #expect(sweeping(.bFlat) { $0.key = .major(.bFlat) }.prompt?.noteName == "B♭")
        #expect(sweeping(.bFlat).prompt?.noteName == "A♯")
    }

    @Test func nothingInRangeGivesAReason() {
        // Frets 0–12 with the capo at 12 leave one fret: E♭ standard has no naturals there on string 6.
        var options = DrillOptions()
        options.strings = [0]
        let setup = DrillSetup(fretboard: Fretboard(tuning: TuningPreset.eFlatStandard.tuning, capo: 12), options: options, seed: 1)
        #expect(DrillKind.allInstances.makeDrill(setup).nothingToPromptReason != nil)
    }
}

@Suite("All instances: answers")
struct SweepAnswerTests {
    @Test func aWrongNoteIsNamedAndKeepsTheLocation() {
        var drill = sweeping(.c)
        drill.handle(.played(Pitch(43), onset: s(1), at: s(1.1)))
        #expect(drill.phase == .wrong(PitchClass(7)))
        #expect(drill.prompt?.target == at(0, 8))
        #expect(drill.display?.feedback == "You played G")
        #expect(drill.display?.result == .wrong)
        drill.handle(.played(Pitch(48), onset: s(2), at: s(2.1)))
        #expect(drill.attempts.first?.firstRight == false)
        #expect(drill.attempts.first?.rawWrongAnswers == [.played(Pitch(43))])
        #expect(drill.prompt?.target == at(1, 3))
    }

    @Test func anotherOctaveIsWrong() {
        var drill = sweeping(.c)
        drill.handle(.played(Pitch(60), onset: s(1), at: s(1.1)))
        #expect(drill.phase == .wrong(PitchClass(0)))
        #expect(drill.prompt?.target == at(0, 8))
    }

    @Test func theSamePitchOnTheNextStringNeedsANewPlayedNote() {
        var drill = sweeping(.c)
        drill.handle(.played(Pitch(48), onset: s(1), at: s(1.1)))
        #expect(drill.prompt?.target == at(1, 3))
        drill.handle(.tick(at: s(3)))
        #expect(drill.prompt?.target == at(1, 3))
        #expect(drill.attempts.count == 1)
        drill.handle(.played(Pitch(48), onset: s(3.5), at: s(3.6)))
        #expect(drill.attempts.map(\.location) == [at(0, 8), at(1, 3)])
        #expect(drill.attempts.map(\.responseTime) == [s(1), s(2.5)])
    }

    @Test func aNoteRingingFromBeforeASkipDoesNotCount() {
        var drill = sweeping(.c)
        drill.handle(.skip(at: s(2)))
        drill.handle(.played(Pitch(48), onset: s(1.95), at: s(2.1)))
        #expect(drill.attempts.map(\.outcome) == [.skipped])
        #expect(drill.phase == .waiting)
    }

    @Test func aLocationTimesOutAfter10sIsRevealedAndTheSweepMovesOn() throws {
        var drill = sweeping(.c)
        drill.handle(.tick(at: s(10.1)))
        #expect(drill.attempts.isEmpty)
        drill.handle(.tick(at: s(10.2)))
        #expect(drill.attempts.map(\.outcome) == [.timedOut])
        #expect(drill.prompt?.target == at(1, 3))
        #expect(drill.promptStart == s(10))
        let display = try #require(drill.display)
        #expect(display.markers == [.init(location: at(0, 8), label: "C", isAnswer: false)])
        #expect(display.feedback == "Time's up — it was fret 8")
        #expect(display.chips[0] == .init(title: "6", text: "fret 8", state: .timedOut))
    }

    @Test func skipLeavesOneLocationUnrevealed() throws {
        var drill = sweeping(.c)
        drill.handle(.skip(at: s(4)))
        #expect(drill.attempts.map(\.outcome) == [.skipped])
        #expect(drill.prompt?.target == at(1, 3))
        #expect(drill.promptStart == s(4))
        let display = try #require(drill.display)
        #expect(display.markers.isEmpty)
        #expect(display.chips[0] == .init(title: "6", text: "skip", state: .skipped))
    }

    @Test func attemptsShareTheirSweepsNumberAndTheNextSweepHasAnother() {
        var drill = sweeping(.c)
        finishSweep(&drill)
        drill.handle(.tick(at: s(20)))
        finishSweep(&drill, from: 20)
        #expect(drill.attempts.prefix(6).allSatisfy { $0.prompt.sweep == 0 })
        #expect(drill.attempts.dropFirst(6).allSatisfy { $0.prompt.sweep == 1 })
        #expect(drill.attempts.prefix(6).map(\.prompt.target) == everyC)
    }

    @Test func resumeContinuesAtTheSameLocationWithItsTimerRestarted() {
        var drill = sweeping(.c)
        drill.handle(.played(Pitch(48), onset: s(1), at: s(1.1)))
        drill.handle(.pause(at: s(5)))
        #expect(drill.prompt == nil)
        #expect(drill.display == nil)
        #expect(drill.resumesSamePrompt)
        drill.handle(.resume(at: s(60)))
        #expect(drill.prompt?.target == at(1, 3))
        #expect(drill.prompt?.sweep == 0)
        #expect(drill.timeRemaining(at: s(60)) == s(10))
        drill.handle(.played(Pitch(48), onset: s(62), at: s(62.1)))
        #expect(drill.attempts.map(\.responseTime) == [s(1), s(2)])
    }

    @Test func pausingBetweenSweepsResumesWithTheNextOne() {
        var drill = sweeping(.c)
        finishSweep(&drill)
        drill.handle(.pause(at: s(6.5)))
        #expect(!drill.resumesSamePrompt)
        drill.handle(.resume(at: s(9)))
        #expect(drill.prompt?.sweep == 1)
        #expect(drill.prompt?.pitchClass != PitchClass(0))
        #expect(drill.promptStart == s(9))
    }

    @Test func noteToPlayItResumesOnANewPrompt() {
        var drill = DrillKind.notePlayIt.makeDrill(DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1))
        drill.handle(.start(at: s(0)))
        drill.handle(.pause(at: s(1)))
        #expect(!drill.resumesSamePrompt)
    }
}

@Suite("All instances: sweeps in a run")
struct SweepRunTests {
    @Test func repeatStartsTheNoteAgainAsANewSweepAndKeepsTheAttempts() {
        var drill = sweeping(.c)
        drill.handle(.played(Pitch(48), onset: s(1), at: s(1.1)))
        drill.handle(.repeat(at: s(3)))
        #expect(drill.prompt?.target == at(0, 8))
        #expect(drill.prompt?.sweep == 1)
        #expect(drill.promptStart == s(3))
        #expect(drill.attempts.count == 1)
        #expect(drill.display?.markers == [])
    }

    @Test func onlyCompleteSweepsHaveATotalTime() {
        var drill = sweeping(.c)
        drill.handle(.played(Pitch(48), onset: s(1), at: s(1.1)))
        drill.handle(.repeat(at: s(3)))
        finishSweep(&drill, from: 3)
        #expect(drill.sweeps.map(\.noteName) == ["C", "C"])
        #expect(drill.sweeps.map(\.totalTime) == [nil, s(6)])
        #expect(drill.sweeps.map(\.summaryLine) == ["Every C — 1 of 6", "Every C — 6.00 s"])
    }

    @Test func aTimeoutCountsItsTenSecondsInTheTotal() {
        var drill = sweeping(.c)
        drill.handle(.tick(at: s(10.2)))
        finishSweep(&drill, from: 10)
        #expect(drill.sweeps.map(\.totalTime) == [s(15)])
    }

    @Test func aSkipLeavesASweepIncomplete() {
        var drill = sweeping(.c)
        drill.handle(.skip(at: s(1)))
        finishSweep(&drill, from: 1)
        #expect(drill.sweeps.map(\.totalTime) == [nil])
        #expect(drill.display?.feedback == "Every C — 5 of 6")
    }

    @Test func otherDrillsHaveNoSweeps() {
        var drill: any Drill = lowEDrill()
        drill.handle(.played(Pitch(40), onset: s(1), at: s(1.1)))
        #expect(drill.sweeps.isEmpty)
    }

    @Test func theTotalIsShownForAMomentThenTheNextSweepStartsAfresh() {
        var drill = sweeping(.c)
        finishSweep(&drill)   // the last onset at 6.0, detected at 6.1
        #expect(drill.display?.result == .right)
        #expect(drill.display?.feedback == "Every C — 6.00 s")
        drill.handle(.tick(at: s(7.8)))
        #expect(drill.prompt?.sweep == 0)
        drill.handle(.tick(at: s(7.9)))
        #expect(drill.prompt?.sweep == 1)
        #expect(drill.promptStart == s(7.9))
    }

    @Test func aLastLocationTimingOutIsRevealed() {
        var drill = sweeping(.c) { $0.options.strings = [0] }
        drill.handle(.tick(at: s(10.2)))
        #expect(drill.phase == .timedOut)
        #expect(drill.display?.markers.map(\.location) == [at(0, 8)])
        #expect(drill.display?.feedback == "Time's up — it was fret 8 · Every C — 10.00 s")
        drill.handle(.tick(at: s(12)))
        #expect(drill.prompt?.sweep == 1)
    }

    @Test func noNoteIsSweptAgainUntilAllHaveBeen() {
        for seed in UInt64(0)..<20 {
            var setup = DrillSetup(fretboard: Fretboard(tuning: .standard), seed: seed)
            setup.weighting = NoteWeighting(preferred: [PitchClass(0)], share: 0.7)
            var drill = DrillKind.allInstances.makeDrill(setup)
            drill.handle(.start(at: s(0)))
            var notes: [PitchClass] = []
            for sweep in 0..<21 {
                let time = Double(sweep) * 20
                notes.append(drill.prompt!.pitchClass)
                finishSweep(&drill, from: time)
                drill.handle(.tick(at: s(time + 19)))
            }
            for start in [0, 7, 14] { #expect(Set(notes[start..<start + 7]).count == 7) }
            #expect(zip(notes, notes.dropFirst()).allSatisfy { $0 != $1 })
        }
    }

    @Test func preferredNotesAreSweptFirstMoreOften() {
        let preferredFirst = (UInt64(0)..<1000).filter { seed in
            var setup = DrillSetup(fretboard: Fretboard(tuning: .standard), seed: seed)
            setup.weighting = NoteWeighting(preferred: [PitchClass(0), PitchClass(7)], share: 0.7)
            var drill = DrillKind.allInstances.makeDrill(setup)
            drill.handle(.start(at: s(0)))
            return [0, 7].contains(drill.prompt!.pitchClass.value)
        }
        #expect((640...760).contains(preferredFirst.count))
    }
}

@Suite("All instances: display")
struct SweepDisplayTests {
    @Test func theNextStringIsNamedAndLitAndFoundLocationsStayLit() throws {
        var drill = sweeping(.c)
        var display = try #require(drill.display)
        #expect(display.headline == "Every C")
        #expect(display.subline == "next: string 6 (E) · 1 of 6")
        #expect(display.feedback == "Listening…")
        #expect(display.highlightedString == 0)
        #expect(display.markers.isEmpty)
        #expect(display.chips.map(\.title) == ["6", "5", "4", "3", "2", "1"])
        #expect(display.chips.map(\.text) == ["–", "–", "–", "–", "–", "–"])
        #expect(display.chips.map(\.state) == [.current, .waiting, .waiting, .waiting, .waiting, .waiting])

        drill.handle(.played(Pitch(48), onset: s(1), at: s(1.1)))
        drill.handle(.played(Pitch(48), onset: s(2.5), at: s(2.6)))
        display = try #require(drill.display)
        #expect(display.subline == "next: string 4 (D) · 3 of 6")
        #expect(display.feedback == "Fret 3 · 1.50 s")
        #expect(display.result == .waiting)
        #expect(display.highlightedString == 2)
        #expect(display.markers == [.init(location: at(0, 8), label: "C", isAnswer: true),
                                    .init(location: at(1, 3), label: "C", isAnswer: true)])
        #expect(display.chips.map(\.state) == [.found, .found, .current, .waiting, .waiting, .waiting])
        #expect(display.chips.map(\.text) == ["fret 8", "fret 3", "–", "–", "–", "–"])
    }

    @Test func aFinishedSweepShowsEveryLocation() throws {
        var drill = sweeping(.c)
        finishSweep(&drill)
        let display = try #require(drill.display)
        #expect(display.markers.map(\.location) == everyC)
        #expect(display.subline == "6 of 6")
        #expect(display.highlightedString == nil)
        #expect(display.chips.map(\.state) == Array(repeating: .found, count: 6))
    }
}
