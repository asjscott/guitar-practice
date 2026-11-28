import Testing
import TheoryCore
import PracticeCore

private func at(_ string: Int, _ fret: Int) -> FretboardLocation { FretboardLocation(string: string, fret: fret) }

/// A Note circle from a key, started at 0.
private func circle(from key: Key, on fretboard: Fretboard = Fretboard(tuning: .standard),
                    _ change: (inout DrillSetup) -> Void = { _ in }) -> any Drill {
    var setup = DrillSetup(fretboard: fretboard, key: key, seed: 1)
    change(&setup)
    var drill = DrillKind.noteCircle.makeDrill(setup)
    drill.handle(.start(at: s(0)))
    return drill
}

/// Plays the prompted pitch a second after each prompt's timer starts, until the sweep ends or the circle does;
/// returns the sweep's locations in order.
@discardableResult
private func finishSweep(_ drill: inout any Drill) -> [FretboardLocation] {
    var found: [FretboardLocation] = []
    let sweep = drill.prompt?.sweep
    while [.waiting, .wrong].contains(drill.display?.result), drill.prompt?.sweep == sweep, let target = drill.prompt?.target,
          let start = drill.promptStart, found.count < 100 {
        found.append(target)
        drill.handle(.played(drill.fretboard.pitch(at: target), onset: start + s(1), at: start + s(1.1)))
        // Past the pause between sweeps, so that the next one's first prompt is up.
        drill.handle(.tick(at: start + s(1.6)))
    }
    return found
}

/// Standard tuning, frets 0–12.
private let everyE = [at(0, 0), at(0, 12), at(1, 7), at(2, 2), at(3, 9), at(4, 5), at(5, 0), at(5, 12)]
private let everyB = [at(0, 7), at(1, 2), at(2, 9), at(3, 4), at(4, 0), at(4, 12), at(5, 7)]

@Suite("Note circle: prompts")
struct NoteCirclePromptTests {
    @Test func isInThePickerWithAnIdThatNeverChanges() {
        #expect(DrillKind.all.contains(.noteCircle))
        #expect(DrillKind.noteCircle.id == "noteCircle")
        #expect(DrillKind.noteCircle.module == .notes)
        #expect(DrillKind.noteCircle.goesRoundTheCircle)
        #expect(!DrillKind.allInstances.goesRoundTheCircle)
    }

    @Test func eachKeysTonicFromString6LowestFretFirstThenTheNextKey() {
        var drill = circle(from: .major(.e))
        #expect(finishSweep(&drill) == everyE)
        #expect(finishSweep(&drill) == everyB)
    }

    @Test func twelveSweepsRoundTheCircleSpelledAsTheAppsKeys() {
        var drill = circle(from: .major(.e))
        var names: [String] = []
        for _ in 0..<12 {
            names.append(drill.prompt?.noteName ?? "–")
            finishSweep(&drill)
        }
        #expect(names == ["E", "B", "F♯", "D♭", "A♭", "E♭", "B♭", "F", "C", "G", "D", "A"])
    }

    @Test func aMinorKeyWalksTheMinorKeys() {
        var drill = circle(from: .minor(.cSharp))
        var keys: [String] = []
        for _ in 0..<4 {
            keys.append(drill.display?.circle?.key.shortName ?? "–")
            finishSweep(&drill)
        }
        #expect(keys == ["C♯m", "G♯m", "D♯m", "B♭m"])
    }

    @Test func withoutAKeyItStartsFromTheOptionsKey() {
        var setup = DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1)
        setup.options.key = .major(.g)
        var drill = DrillKind.noteCircle.makeDrill(setup)
        drill.handle(.start(at: s(0)))
        #expect(drill.prompt?.noteName == "G")
    }

    @Test func aThemeStartsItAtTheThemesKey() {
        var setup = DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1)
        setup.follow(Theme(key: .major(.a), position: .init(system: .caged, number: 1)))
        var drill = DrillKind.noteCircle.makeDrill(setup)
        drill.handle(.start(at: s(0)))
        #expect(drill.prompt?.noteName == "A")
    }

    @Test func overTwelveFretsFromTheCapoWhateverTheOptions() {
        var drill = circle(from: .major(.e), on: Fretboard(tuning: .standard, capo: 5)) {
            $0.options.frets = 0...22
            $0.options.strings = [0]
            $0.options.notes = .naturals
        }
        #expect(finishSweep(&drill) == [at(0, 12), at(1, 7), at(2, 14), at(3, 9), at(4, 5), at(4, 17), at(5, 12)])
    }

    @Test(arguments: [TuningPreset.dropD, .dadgad, .openG], [0, 3, 10])
    func everySweepHasEveryInstanceOnceInRange(preset: TuningPreset, capo: Int) {
        let fretboard = Fretboard(tuning: preset.tuning, capo: capo)
        var drill = circle(from: .major(.d), on: fretboard)
        for key in Key.major(.d).circleOfFifths {
            let expected = fretboard.locations(of: key.tonic.pitchClass)
                .filter { (capo...capo + 12).contains($0.fret) }
                .sorted { ($0.string, $0.fret) < ($1.string, $1.fret) }
            #expect(finishSweep(&drill) == expected)
        }
        drill.handle(.tick(at: s(10_000)))
        #expect(!drill.isRunning)
    }
}

@Suite("Note circle: answers")
struct NoteCircleAnswerTests {
    @Test func aLocationNeverTimesOut() {
        var drill = circle(from: .major(.e))
        #expect(drill.timeRemaining(at: s(1)) == nil)
        drill.handle(.tick(at: s(600)))
        #expect(drill.attempts.isEmpty)
        #expect(drill.phase == .waiting)
        #expect(drill.prompt?.target == at(0, 0))
    }

    @Test func aWrongNoteIsCountedAndKeepsTheLocation() throws {
        var drill = circle(from: .major(.e))
        drill.handle(.played(Pitch(41), onset: s(1), at: s(1.1)))
        #expect(drill.phase == .wrong(PitchClass(5)))
        #expect(try #require(drill.display?.circle).wrongNotes == 1)
        drill.handle(.played(Pitch(40), onset: s(2), at: s(2.1)))
        #expect(drill.attempts.map(\.firstRight) == [false])
        #expect(try #require(drill.display?.circle).wrongNotes == 1)
        #expect(drill.prompt?.target == at(0, 12))
    }

    @Test func aSkipMovesOnAndTheCircleIsNotClean() throws {
        var drill = circle(from: .major(.e))
        drill.handle(.skip(at: s(3)))
        #expect(drill.attempts.map(\.outcome) == [.skipped])
        #expect(drill.prompt?.target == at(0, 12))
        #expect(try #require(drill.display?.circle).skips == 1)
        for _ in 0..<12 { finishSweep(&drill) }
        let result = try #require(CircleResult(attempts: drill.attempts))
        #expect(result.isComplete)
        #expect(!result.isClean)
    }

    @Test func oneAttemptPerLocationGroupedBySweepInOneCircle() throws {
        var drill = circle(from: .major(.e))
        finishSweep(&drill)
        finishSweep(&drill)
        let attempts = drill.attempts
        #expect(attempts.count == everyE.count + everyB.count)
        #expect(attempts.map(\.location) == everyE + everyB)
        #expect(attempts.prefix(8).allSatisfy { $0.group?.number == 0 && $0.group?.size == 8 })
        #expect(attempts.dropFirst(8).allSatisfy { $0.group?.number == 1 && $0.group?.size == 7 })
        #expect(attempts.prefix(8).map(\.group?.place) == Array(0..<8))
        #expect(attempts.allSatisfy { $0.group?.circle == 0 })
        #expect(attempts.allSatisfy { $0.facts == nil })
    }

    @Test func pausingKeepsTheLocationAndItsWrongNotes() {
        var drill = circle(from: .major(.e))
        drill.handle(.played(Pitch(41), onset: s(1), at: s(1.1)))
        drill.handle(.pause(at: s(2)))
        #expect(drill.resumesSamePrompt)
        drill.handle(.resume(at: s(30)))
        #expect(drill.prompt?.target == at(0, 0))
        drill.handle(.played(Pitch(40), onset: s(31), at: s(31.1)))
        #expect(drill.attempts.map(\.wrongNotes) == [[PitchClass(5)]])
        #expect(drill.attempts.map(\.responseTime) == [s(1)])
    }
}

@Suite("Note circle: time, wrong notes and the best")
struct NoteCircleTimeTests {
    @Test func theClockRunsOnThroughASweepAndIntoTheNext() throws {
        var drill = circle(from: .major(.e))
        #expect(try #require(drill.display?.circle).time(at: s(0.5)) == s(0.5))
        drill.handle(.played(Pitch(40), onset: s(1), at: s(1.1)))
        #expect(try #require(drill.display?.circle).time(at: s(1.5)) == s(1.5))
        finishSweep(&drill)
        // The B sweep's first location times from the E sweep's last onset: the pause between sweeps counts.
        let clock = try #require(drill.display?.circle)
        #expect(clock.key.shortName == "B")
        #expect(clock.place == 1)
        #expect(drill.promptStart == s(8))
        #expect(clock.time(at: s(9)) == s(9))
    }

    @Test func pausedTimeIsNotCounted() throws {
        var drill = circle(from: .major(.e))
        drill.handle(.played(Pitch(40), onset: s(1), at: s(1.1)))
        drill.handle(.pause(at: s(2)))
        drill.handle(.resume(at: s(50)))
        #expect(try #require(drill.display?.circle).time(at: s(51)) == s(2))
    }

    @Test func theKeyItsPlaceAndTheNextKey() throws {
        var drill = circle(from: .major(.e))
        var circle = try #require(drill.display?.circle)
        #expect(circle.key == .major(.e))
        #expect(circle.next == .major(.b))
        #expect(circle.place == 0)
        #expect(circle.count == 12)
        for _ in 0..<11 { finishSweep(&drill) }
        circle = try #require(drill.display?.circle)
        #expect(circle.key == .major(.a))
        #expect(circle.place == 11)
        #expect(circle.next == nil)
    }

    @Test func theCircleEndsWithItsTotalTimeAndWrongNotesThenTheRunStops() throws {
        var drill = circle(from: .major(.e))
        drill.handle(.played(Pitch(41), onset: s(0.5), at: s(0.6)))
        var locations = 0
        for _ in 0..<12 { locations += finishSweep(&drill).count }
        // Each location a second after the last, the pauses between sweeps included.
        let circle = try #require(drill.display?.circle)
        let result = try #require(circle.result)
        #expect(result.time == s(Double(locations)))
        #expect(result.wrongNotes == 1)
        #expect(!result.isClean)
        #expect(circle.time(at: s(500)) == result.time)
        #expect(drill.isRunning)
        drill.handle(.tick(at: s(Double(locations) + 2)))
        #expect(!drill.isRunning)
        #expect(CircleResult(attempts: drill.attempts) == result)
    }

    @Test func theBestIsShownAndBeatenByAFasterCleanCircle() throws {
        let best = CircleResult(time: .seconds(500), wrongNotes: 0, skips: 0, isComplete: true)
        var drill = circle(from: .major(.e)) { $0.circleBest = best }
        #expect(drill.display?.circle?.best == best)
        for _ in 0..<12 { finishSweep(&drill) }
        let result = try #require(drill.display?.circle?.result)
        #expect(result.isBetter(than: best))
        #expect(!best.isBetter(than: result))
    }

    @Test func onlyAFinishedCleanCircleCanBeTheBest() {
        let clean = CircleResult(time: .seconds(500), wrongNotes: 0, skips: 0, isComplete: true)
        let skipped = CircleResult(time: .seconds(400), wrongNotes: 0, skips: 1, isComplete: true)
        let wrong = CircleResult(time: .seconds(300), wrongNotes: 1, skips: 0, isComplete: true)
        let unfinished = CircleResult(time: .seconds(100), wrongNotes: 0, skips: 0, isComplete: false)
        let faster = CircleResult(time: .seconds(450), wrongNotes: 0, skips: 0, isComplete: true)
        #expect(!wrong.isClean)
        #expect(CircleResult.best(of: [clean, skipped, wrong, unfinished]) == clean)
        #expect(CircleResult.best(of: [clean, faster]) == faster)
        #expect(CircleResult.best(of: [skipped, wrong, unfinished]) == nil)
        #expect(clean.isBetter(than: nil))
        #expect(!skipped.isBetter(than: nil))
        #expect(!wrong.isBetter(than: clean))
    }

    @Test func aCircleStoppedPartWayIsNotComplete() throws {
        var drill = circle(from: .major(.e))
        finishSweep(&drill)
        drill.handle(.stop(at: s(20)))
        let result = try #require(CircleResult(attempts: drill.attempts))
        #expect(!result.isComplete)
        #expect(result.time == s(8))
    }

    @Test func aCircleFromTheLogsParts() {
        // Two sweeps of a two-sweep circle: the second is missing an attempt, then has it.
        let parts = [
            CircleResult.Part(group: 0, groupSize: 2, outcome: .answered, responseTime: s(1), wrongNotes: 1),
            CircleResult.Part(group: 0, groupSize: 2, outcome: .answered, responseTime: s(2), wrongNotes: 0),
            CircleResult.Part(group: 1, groupSize: 2, outcome: .skipped, responseTime: nil, wrongNotes: 0),
        ]
        let partWay = CircleResult(parts: parts, count: 2)
        #expect(partWay == CircleResult(time: s(3), wrongNotes: 1, skips: 1, isComplete: false))
        let done = parts + [CircleResult.Part(group: 1, groupSize: 2, outcome: .answered, responseTime: s(4), wrongNotes: 2)]
        #expect(CircleResult(parts: done, count: 2) == CircleResult(time: s(7), wrongNotes: 3, skips: 1, isComplete: true))
    }
}
