import Testing
import TheoryCore
import PracticeCore

private func at(_ string: Int, _ fret: Int) -> FretboardLocation { FretboardLocation(string: string, fret: fret) }

/// A Triad circle from a key on one string set, frets 0–12 unless changed, started at 0.
private func circle(from key: Key, on set: StringSet = .dGB, fretboard: Fretboard = Fretboard(tuning: .standard),
                    _ change: (inout DrillSetup) -> Void = { _ in }) -> any Drill {
    var setup = DrillSetup(fretboard: fretboard, key: key, seed: 1)
    setup.options.stringSets = [set]
    change(&setup)
    var drill = DrillKind.triadCircle.makeDrill(setup)
    drill.handle(.start(at: s(0)))
    return drill
}

/// Plays each prompted note a second after its timer starts, until the key's climb ends or the circle does; returns
/// the climb's voicings as their frets, low string first.
@discardableResult
private func finishClimb(_ drill: inout any Drill) -> [[Int]] {
    var frets: [Int] = []
    let place = drill.display?.circle?.place
    while [.waiting, .wrong].contains(drill.display?.result), drill.display?.circle?.place == place,
          let target = drill.prompt?.target, let start = drill.promptStart, frets.count < 300 {
        frets.append(target.fret)
        drill.handle(.played(drill.fretboard.pitch(at: target), onset: start + s(1), at: start + s(1.1)))
        // Past any pause, so that the next prompt is up.
        drill.handle(.tick(at: start + s(1.6)))
    }
    return stride(from: 0, to: frets.count, by: 3).map { Array(frets[$0..<min($0 + 3, frets.count)]) }
}

/// The triad of the climb that is up: "E major".
private func triadAsked(_ drill: any Drill) -> String? {
    drill.display.map { String($0.headline.prefix { $0 != "·" }.dropLast()) }
}

/// E major on D-G-B, frets 0–12: root position at 2 1 0, 1st inversion at 6 4 5, 2nd at 9 9 9.
private let eMajor = [[2, 1, 0], [6, 4, 5], [9, 9, 9], [6, 4, 5], [2, 1, 0]]
/// B major: 2nd inversion at 4 4 4, root position at 9 8 7.
private let bMajor = [[4, 4, 4], [9, 8, 7], [4, 4, 4]]

@Suite("Triad circle: climbs")
struct TriadCircleClimbTests {
    @Test func isInThePickerWithAnIdThatNeverChanges() {
        #expect(DrillKind.all.contains(.triadCircle))
        #expect(DrillKind.triadCircle.id == "triadCircle")
        #expect(DrillKind.triadCircle.module == .triads)
        #expect(DrillKind.triadCircle.goesRoundTheCircle)
        #expect(DrillKind.triadCircle.hasClimbs)
        #expect(DrillKind.triadCircle.fades)
        #expect(DrillKind.triadCircle.repeatTitle == nil)
    }

    @Test func eachKeysTonicTriadUpAndBackThenTheNextKey() {
        var drill = circle(from: .major(.e))
        #expect(triadAsked(drill) == "E major")
        #expect(finishClimb(&drill) == eMajor)
        #expect(triadAsked(drill) == "B major")
        #expect(finishClimb(&drill) == bMajor)
    }

    @Test func twelveClimbsRoundTheCircleSpelledAsTheAppsKeys() {
        var drill = circle(from: .major(.e))
        var asked: [String] = []
        for _ in 0..<12 {
            asked.append(triadAsked(drill) ?? "–")
            finishClimb(&drill)
        }
        #expect(asked == ["E major", "B major", "F♯ major", "D♭ major", "A♭ major", "E♭ major", "B♭ major", "F major",
                          "C major", "G major", "D major", "A major"])
        drill.handle(.tick(at: s(10_000)))
        #expect(!drill.isRunning)
    }

    @Test func aMinorKeyClimbsMinorTriads() {
        var drill = circle(from: .minor(.cSharp))
        var asked: [String] = []
        for _ in 0..<4 {
            asked.append(triadAsked(drill) ?? "–")
            finishClimb(&drill)
        }
        #expect(asked == ["C♯ minor", "G♯ minor", "D♯ minor", "B♭ minor"])
    }
}

@Suite("Triad circle: string set and frets")
struct TriadCircleRangeTests {
    @Test func theFirstIncludedStringSetAndTheSetupsFrets() {
        var drill = circle(from: .major(.e), on: .gBE) {
            $0.options.stringSets = [.gBE, .dGB]
            $0.options.frets = 0...7
        }
        // E major on D-G-B to fret 7: 2 1 0 and 6 4 5.
        #expect(drill.display?.subline.hasPrefix("voicing 1 of 3") == true)
        #expect(drill.display?.highlightedStrings == [2, 3, 4])
        #expect(finishClimb(&drill) == [[2, 1, 0], [6, 4, 5], [2, 1, 0]])
    }

    @Test func aThemesStringSet() {
        var setup = DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1)
        setup.follow(Theme(key: .major(.e), position: .init(system: .caged, number: 1), stringSet: .dGB))
        var drill = DrillKind.triadCircle.makeDrill(setup)
        drill.handle(.start(at: s(0)))
        #expect(triadAsked(drill) == "E major")
        #expect(finishClimb(&drill) == eMajor)
    }

    @Test func aKeyWithoutTwoVoicingsInRangeIsAReasonNotToStart() {
        var options = DrillOptions()
        options.stringSets = [.dGB]
        options.frets = 0...3
        let drill = DrillKind.triadCircle.makeDrill(DrillSetup(fretboard: Fretboard(tuning: .standard), options: options, seed: 1))
        #expect(drill.nothingToPromptReason == "Not every key’s triad has two voicings in these frets on this string set.")
        #expect(circle(from: .major(.e)).nothingToPromptReason == nil)
    }

    @Test func aSetWhereAKeysTriadDoesntFitIsPassedOver() {
        // In Drop D, E-A-D holds one voicing of most triads and none of some.
        let dropD = Fretboard(tuning: TuningPreset.dropD.tuning)
        let drill = circle(from: .major(.e), fretboard: dropD) { $0.options.stringSets = [.eAD, .gBE] }
        #expect(drill.display?.highlightedStrings == [3, 4, 5])
        var onlyEAD = DrillSetup(fretboard: dropD, key: .major(.e), seed: 1)
        onlyEAD.options.stringSets = [.eAD]
        #expect(DrillKind.triadCircle.makeDrill(onlyEAD).nothingToPromptReason != nil)
    }

    /// With every set included: the first that holds every key's climb.
    @Test(arguments: [(TuningPreset.dropD, StringSet.aDG), (.dadgad, .aDG), (.openG, .dGB)], [0, 3])
    func everyClimbIsEveryVoicingInRangeUpAndBack(_ tuning: (preset: TuningPreset, set: StringSet), capo: Int) throws {
        let fretboard = Fretboard(tuning: tuning.preset.tuning, capo: capo)
        let set = tuning.set
        var drill = circle(from: .major(.d), fretboard: fretboard) {
            $0.options.stringSets = Set(StringSet.allCases)
            $0.options.frets = 0...22
        }
        try #require(drill.nothingToPromptReason == nil)
        #expect(drill.display?.highlightedStrings == Set(set.strings))
        for key in Key.major(.d).circleOfFifths {
            let up = fretboard.voicings(of: Triad(.major, root: key.tonic), on: set, frets: 0...22)
                .map { $0.locations.map(\.fret) }
            #expect(up.count >= 2)
            #expect(finishClimb(&drill) == up + up.dropLast().reversed())
        }
        for attempt in drill.attempts {
            guard case .triad(let facts) = attempt.facts, let location = attempt.location else {
                Issue.record("A triad's note")
                continue
            }
            let pitchClasses = facts.triad.tones(in: .root).map(\.pitchClass)
            #expect(pitchClasses.contains(fretboard.pitch(at: location).pitchClass))
            #expect(location.fret >= capo && location.fret <= 22)
            #expect(set.strings.contains(location.string))
        }
    }
}

@Suite("Triad circle: attempts")
struct TriadCircleAttemptTests {
    @Test func oneAttemptPerNoteGroupedByClimbInOneCircle() throws {
        var drill = circle(from: .major(.e))
        finishClimb(&drill)
        finishClimb(&drill)
        let attempts = drill.attempts
        #expect(attempts.map { $0.location?.fret } == (eMajor + bMajor).flatMap { $0 })
        #expect(attempts.prefix(15).allSatisfy { $0.group?.number == 0 && $0.group?.size == 15 })
        #expect(attempts.dropFirst(15).allSatisfy { $0.group?.number == 1 && $0.group?.size == 9 })
        #expect(attempts.prefix(15).map(\.group?.place) == Array(0..<15))
        #expect(attempts.allSatisfy { $0.group?.circle == 0 })
        guard case .triad(let facts) = try #require(attempts.first?.facts) else {
            Issue.record("Not a triad's facts")
            return
        }
        #expect(facts.triad == Triad(.major, root: .e))
        #expect(facts.inversion == .root)
        #expect(facts.stringSet == .dGB)
        #expect(facts.fadeLevel == .first)
    }

    @Test func aNoteNeverTimesOut() {
        var drill = circle(from: .major(.e)) { $0.options.triadFade = FadeLevel(3) }
        #expect(drill.timeRemaining(at: s(1)) == nil)
        drill.handle(.tick(at: s(600)))
        #expect(drill.attempts.isEmpty)
        #expect(drill.prompt?.target == at(2, 2))
    }

    @Test func aSkipMovesOnToTheNextNoteAndTheCircleIsNotClean() throws {
        var drill = circle(from: .major(.e))
        drill.handle(.skip(at: s(3)))
        #expect(drill.attempts.map(\.outcome) == [.skipped])
        #expect(drill.prompt?.target == at(3, 1))
        #expect(drill.display?.chips.map(\.state) == [.skipped, .current, .waiting])
        #expect(try #require(drill.display?.circle).skips == 1)
        for _ in 0..<12 { finishClimb(&drill) }
        let result = try #require(CircleResult(attempts: drill.attempts))
        #expect(result.isComplete)
        #expect(!result.isClean)
    }

    @Test func pausingKeepsTheNoteAndItsWrongNotes() {
        var drill = circle(from: .major(.e))
        drill.handle(.played(Pitch(52), onset: s(1), at: s(1.1)))
        drill.handle(.played(Pitch(57), onset: s(2), at: s(2.1)))
        drill.handle(.pause(at: s(3)))
        #expect(drill.resumesSamePrompt)
        drill.handle(.resume(at: s(30)))
        #expect(drill.prompt?.target == at(3, 1))
        drill.handle(.played(Pitch(56), onset: s(31), at: s(31.1)))
        #expect(drill.attempts.map(\.wrongNotes) == [[], [PitchClass(9)]])
        #expect(drill.attempts.map(\.responseTime) == [s(1), s(1)])
    }
}

@Suite("Triad circle: fade")
struct TriadCircleFadeTests {
    private func markers(_ drill: inout any Drill, at time: Double) -> [DrillDisplay.Marker] {
        drill.handle(.tick(at: s(time)))
        return drill.display?.markers ?? []
    }

    @Test func aNewShapeStartsAtLevel0FullyShownWithItsRootMarked() {
        var drill = circle(from: .major(.e))
        let shown = markers(&drill, at: 60)
        #expect(shown.map(\.location) == [at(2, 2), at(3, 1), at(4, 0)])
        #expect(shown.map(\.label) == ["E", "G♯", "B"])
        #expect(shown.map(\.isAnswer) == [true, false, false])
        #expect(shown.map(\.opacity) == [1, 1, 1])
        #expect(drill.display?.subline == "voicing 1 of 5 · up · Level 0")
    }

    @Test func atALevelTheNotesButTheRootFadeOverItsShareOfTenSeconds() {
        // Level 1 fades by 90 % of 10 s.
        var drill = circle(from: .major(.e)) { $0.options.triadFade = FadeLevel(1) }
        #expect(markers(&drill, at: 4.5).map(\.opacity) == [1, 0.5, 0.5])
        #expect(markers(&drill, at: 9).map(\.location) == [at(2, 2)])
        #expect(drill.display?.subline == "voicing 1 of 5 · up · Level 1")
    }

    @Test func eachVoicingFadesFromWhenItsTimerStarts() {
        var drill = circle(from: .major(.e)) { $0.options.triadFade = FadeLevel(1) }
        for (index, midi) in [52, 56, 59].enumerated() {
            drill.handle(.played(Pitch(midi), onset: s(1 + Double(index)), at: s(1.1 + Double(index))))
        }
        // 1st inversion, timed from the last note at 3 s; its root is E on the B string.
        drill.handle(.tick(at: s(3.5)))
        #expect(drill.prompt?.target == at(2, 6))
        #expect(markers(&drill, at: 7.5).map(\.opacity) == [0.5, 0.5, 1])
    }

    @Test func cleanVoicingsMoveTheirShapeUpOneForTheRun() {
        var drill = circle(from: .major(.e))
        finishClimb(&drill)
        let shape = FadeLevels.VoicingShape(tuning: .standard, quality: .major, inversion: .root, stringSet: .dGB)
        // Root position, clean at the bottom of the climb and again at its end: still played at level 0 this run.
        #expect(drill.fadeLevels?.level(of: shape) == .first)
        #expect(drill.fadeLevels?.levelAfterRun(of: shape) == FadeLevel(1))
    }
}

@Suite("Triad circle: time, wrong notes and the best")
struct TriadCircleTimeTests {
    @Test func theClockRunsOnThroughVoicingsAndKeys() throws {
        var drill = circle(from: .major(.e))
        finishClimb(&drill)
        let clock = try #require(drill.display?.circle)
        #expect(clock.placeText == "B · 2 of 12")
        // Fifteen notes a second apart, each timed from the last.
        #expect(drill.promptStart == s(15))
        #expect(clock.time(at: s(16)) == s(16))
    }

    @Test func aClimbsLastVoicingStaysUpInItsKeyUntilTheNextKey() throws {
        var drill = circle(from: .major(.e))
        for (index, location) in eMajor.joined().enumerated() {
            let onset = s(1 + Double(index))
            let string = [2, 3, 4][index % 3]
            drill.handle(.played(drill.fretboard.pitch(at: at(string, location)), onset: onset, at: onset + s(0.1)))
            if index < 14 { drill.handle(.tick(at: onset + s(0.5))) }
        }
        drill.handle(.tick(at: s(15.2)))
        let display = try #require(drill.display)
        #expect(display.circle?.place == 0)
        #expect(display.headline == "E major · Root position")
        #expect(display.voicings.map(\.state) == Array(repeating: .found, count: 5))
        drill.handle(.tick(at: s(15.5)))
        #expect(drill.display?.circle?.place == 1)
        #expect(drill.display?.voicings.map(\.state).first == .current)
    }

    @Test func theCircleEndsWithItsTimeAndWrongNotesAgainstTheBest() throws {
        let best = CircleResult(time: .seconds(900), wrongNotes: 0, skips: 0, isComplete: true)
        var drill = circle(from: .major(.e)) { $0.circleBest = best }
        drill.handle(.played(Pitch(41), onset: s(0.5), at: s(0.6)))
        var notes = 0
        for _ in 0..<12 { notes += finishClimb(&drill).joined().count }
        let circle = try #require(drill.display?.circle)
        let result = try #require(circle.result)
        #expect(result.time == s(Double(notes)))
        #expect(result.wrongNotes == 1)
        #expect(!result.isClean)
        #expect(!result.isBetter(than: best))
        #expect(circle.best == best)
        #expect(CircleResult(attempts: drill.attempts) == result)
        drill.handle(.tick(at: s(Double(notes) + 2)))
        #expect(!drill.isRunning)
    }
}
