import Testing
import TheoryCore
import PracticeCore

private func at(_ string: Int, _ fret: Int) -> FretboardLocation { FretboardLocation(string: string, fret: fret) }

private func setup(_ preset: TuningPreset = .standard, capo: Int = 0, seed: UInt64 = 1,
                   _ change: (inout DrillOptions) -> Void = { _ in }) -> DrillSetup {
    var options = DrillOptions()
    change(&options)
    return DrillSetup(fretboard: Fretboard(tuning: preset.tuning, capo: capo), options: options, seed: seed)
}

/// A run whose first climb is of one chord on one string set: the first seed that gives it.
private func climbing(_ triad: Triad, on set: StringSet, in preset: TuningPreset = .standard, frets: ClosedRange<Int> = 0...12) -> any Drill {
    for seed in UInt64(0)..<500 {
        var drill = DrillKind.inversions.makeDrill(setup(preset, seed: seed) {
            $0.frets = frets
            $0.stringSets = [set]
        })
        drill.handle(.start(at: s(0)))
        if drill.display?.headline.hasPrefix("\(triad.name) · ") == true { return drill }
    }
    fatalError("No seed asks for \(triad)")
}

/// On D-G-B up to fret 12: 2nd inversion at 2 2 1, root position at 7 5 5, 1st inversion at 10 9 10.
private func aMinor() -> any Drill { climbing(Triad(.minor, root: .a), on: .dGB) }

private let second = [52, 57, 60], root = [57, 60, 64], first = [60, 64, 69]

/// Plays a pitch, heard 0.1 s after its onset.
private func play(_ midi: Int, at time: Double, _ drill: inout any Drill) {
    drill.handle(.played(Pitch(midi), onset: s(time), at: s(time + 0.1)))
}

/// Plays a voicing from `start`, a note every half second, and lets it give way to the next 2 s after `start`.
private func play(_ voicing: [Int], from start: Double, _ drill: inout any Drill) {
    for (index, midi) in voicing.enumerated() { play(midi, at: start + Double(index) * 0.5, &drill) }
    drill.handle(.tick(at: s(start + 2)))
}

private func inversionAsked(_ drill: any Drill) -> String? {
    drill.display.map { String($0.headline.drop { $0 != "·" }.dropFirst(2)) }
}

@Suite("Inversions")
struct InversionsTests {
    @Test func itIsATriadsDrill() {
        #expect(DrillKind.all.contains(.inversions))
        #expect(DrillKind.inversions.id == "inversions")
        #expect(DrillKind.inversions.module == .triads)
        #expect(DrillKind.all.filter(\.hasClimbs) == [.inversions])
        #expect(DrillKind.inversions.repeatTitle == "Restart")
        #expect(!DrillKind.inversions.offersInversions)
        #expect(DrillKind.triadPlayIt.offersInversions)
    }

    @Test func itStartsOnTheLowestVoicingWithItsNotesHidden() throws {
        let display = try #require(aMinor().display)
        #expect(display.headline == "A minor · 2nd inversion")
        #expect(display.subline == "D-G-B")
        #expect(display.highlightedStrings == [2, 3, 4])
        #expect(display.markers.isEmpty)
        #expect(display.chips.map(\.text) == ["?", "?", "?"])
        #expect(display.chips.map(\.state) == [.current, .waiting, .waiting])
        #expect(display.voicings.map(\.title) == ["2nd", "root", "1st", "root", "2nd"])
        #expect(display.voicings.map(\.state) == [.current, .waiting, .waiting, .waiting, .waiting])
        #expect(display.voicings[1].spokenTitle == "voicing 2 of 5")
    }

    @Test func everyVoicingUpAndBackTheHighestOnce() {
        var drill = aMinor()
        var asked: [String?] = []
        for (index, voicing) in [second, root, first, root, second].enumerated() {
            asked.append(inversionAsked(drill))
            play(voicing, from: Double(index) * 3 + 1, &drill)
        }
        #expect(asked == ["2nd inversion", "Root position", "1st inversion", "Root position", "2nd inversion"])
        #expect(drill.attempts.count == 15)
        #expect(drill.attempts.allSatisfy { $0.firstRight })
        // Then another chord.
        #expect(drill.display?.headline.hasPrefix("A minor") == false)
        #expect(drill.display?.voicings.map(\.state).first == .current)
    }

    @Test func theLineShowsTheVoicingsDone() {
        var drill = aMinor()
        play(second, from: 1, &drill)
        #expect(drill.display?.voicings.map(\.state) == [.found, .current, .waiting, .waiting, .waiting])
        play(57, at: 4, &drill)
        #expect(drill.display?.voicings.map(\.state) == [.found, .current, .waiting, .waiting, .waiting])
        #expect(drill.display?.chips.map(\.text) == ["A", "?", "?"])
        #expect(drill.display?.markers == [.init(location: at(2, 7), label: "A", isAnswer: true, isLastPlayed: true)])
    }

    @Test func aRightVoicingShowsWholeThenGivesWay() {
        var drill = aMinor()
        for (index, midi) in second.enumerated() { play(midi, at: Double(index + 1), &drill) }
        #expect(drill.display?.result == .right)
        #expect(drill.display?.feedback == "3.00 s")
        #expect(drill.display?.headline == "A minor · 2nd inversion")
        #expect(drill.display?.markers.map(\.location) == [at(2, 2), at(3, 2), at(4, 1)])
        #expect(drill.display?.voicings.first?.state == .found)
        drill.handle(.tick(at: s(3.5)))
        #expect(drill.phase == .waiting)
        #expect(drill.promptStart == s(3.5))
        #expect(drill.display?.chips.map(\.text) == ["?", "?", "?"])
    }

    @Test func onlyTheVoicingReachedIsRight() {
        var drill = aMinor()
        // The E an octave up, though 2nd inversion can be played there.
        play(64, at: 1, &drill)
        #expect(drill.phase == .wrong(PitchClass(4)))
        #expect(drill.display?.feedback == "You played E, in another octave")
        play(57, at: 2, &drill)
        #expect(drill.display?.feedback == "You played A")
        play(52, at: 3, &drill)
        #expect(drill.attempts.map(\.wrongAnswers) == [[.pitch(Pitch(64)), .pitch(Pitch(57))]])
    }

    @Test func eachNoteIsAnAttemptGroupedByClimbWhichIsOnePrompt() {
        var drill = aMinor()
        for (index, voicing) in [second, root, first, root, second].enumerated() { play(voicing, from: Double(index) * 3 + 1, &drill) }
        #expect(Set(drill.attempts.map { $0.group?.number }).count == 1)
        #expect(drill.attempts.map { $0.group?.place } == Array(0..<15))
        #expect(drill.attempts.allSatisfy { $0.group?.size == 15 })
        #expect(drill.stats.prompts == 1)
        let facts = [Triad.Inversion.second, .root, .first, .root, .second].flatMap { inversion in
            Array(repeating: AttemptFacts.triad(TriadFacts(triad: Triad(.minor, root: .a), inversion: inversion, stringSet: .dGB)), count: 3)
        }
        #expect(drill.attempts.map(\.facts) == facts)
        #expect(drill.attemptsToLog.count == 15)
        drill.handle(.skip(at: s(20)))
        #expect(drill.attempts.last?.group?.number != drill.attempts[0].group?.number)
        #expect(drill.attempts.last?.group?.place == 0)
    }

    @Test func aTimeoutRevealsTheVoicingAndTheClimbMovesOn() {
        var drill = aMinor()
        #expect(drill.timeLimit == s(10))
        play(52, at: 1, &drill)
        drill.handle(.tick(at: s(11.2)))
        #expect(drill.display?.result == .timedOut)
        #expect(drill.display?.markers.map(\.location) == [at(2, 2), at(3, 2), at(4, 1)])
        #expect(drill.display?.chips.map(\.state) == [.found, .timedOut, .timedOut])
        #expect(drill.display?.voicings.first?.state == .timedOut)
        drill.handle(.tick(at: s(13)))
        #expect(inversionAsked(drill) == "Root position")
        #expect(drill.display?.voicings.map(\.state) == [.timedOut, .current, .waiting, .waiting, .waiting])
        play(57, at: 14, &drill)
        #expect(drill.attempts.map(\.outcome) == [.answered, .timedOut, .answered])
        #expect(drill.attempts.map { $0.group?.place } == [0, 1, 3])
    }

    @Test func skipGoesToTheNextVoicing() {
        var drill = aMinor()
        play(52, at: 1, &drill)
        drill.handle(.skip(at: s(2)))
        #expect(drill.attempts.map(\.outcome) == [.answered, .skipped])
        #expect(inversionAsked(drill) == "Root position")
        #expect(drill.display?.voicings.map(\.state) == [.skipped, .current, .waiting, .waiting, .waiting])
        // While a voicing is shown as right, it ends only the pause.
        for (index, midi) in root.enumerated() { play(midi, at: 3 + Double(index) * 0.1, &drill) }
        drill.handle(.skip(at: s(3.35)))
        #expect(inversionAsked(drill) == "1st inversion")
        #expect(drill.stats.skips == 1)
    }

    @Test func repeatRestartsTheClimb() {
        var drill = aMinor()
        play(second, from: 1, &drill)
        play(57, at: 4, &drill)
        drill.handle(.repeat(at: s(5)))
        #expect(drill.display?.headline == "A minor · 2nd inversion")
        #expect(drill.promptStart == s(5))
        #expect(drill.display?.voicings.map(\.state) == [.current, .waiting, .waiting, .waiting, .waiting])
        #expect(drill.attempts.count == 4)
        // A climb of its own in the log.
        play(52, at: 6, &drill)
        #expect(drill.attempts[4].group?.place == 0)
        #expect(drill.attempts[4].group?.number != drill.attempts[3].group?.number)
    }

    @Test func repeatWhileAVoicingIsShownRestartsTheClimb() {
        var drill = aMinor()
        for (index, midi) in second.enumerated() { play(midi, at: Double(index + 1), &drill) }
        drill.handle(.repeat(at: s(3.2)))
        #expect(drill.phase == .waiting)
        #expect(drill.display?.headline == "A minor · 2nd inversion")
        #expect(drill.display?.voicings.map(\.state).first == .current)
    }

    @Test func resumeGoesBackToTheStartOfTheSameVoicing() {
        var drill = aMinor()
        play(second, from: 1, &drill)
        play(57, at: 4, &drill)
        play(62, at: 4.5, &drill)
        drill.handle(.pause(at: s(5)))
        #expect(drill.display == nil)
        #expect(drill.resumesSamePrompt)
        drill.handle(.resume(at: s(9)))
        #expect(drill.phase == .waiting)
        #expect(drill.promptStart == s(9))
        #expect(inversionAsked(drill) == "Root position")
        #expect(drill.display?.chips.map(\.text) == ["?", "?", "?"])
        #expect(drill.display?.voicings.map(\.state) == [.found, .current, .waiting, .waiting, .waiting])
        #expect(drill.attempts.count == 4)
        for (index, midi) in root.enumerated() { play(midi, at: 10 + Double(index), &drill) }
        #expect(drill.display?.result == .right)
        #expect(drill.display?.feedback == "3.00 s")
        #expect(drill.attempts.map { $0.group?.place } == [0, 1, 2, 3, 3, 4, 5])
        #expect(drill.stats.prompts == 1)
    }

    @Test func resumeAfterAVoicingWasDealtWithGoesToTheNext() {
        var drill = aMinor()
        for (index, midi) in second.enumerated() { play(midi, at: Double(index + 1), &drill) }
        drill.handle(.pause(at: s(3.2)))
        #expect(!drill.resumesSamePrompt)
        drill.handle(.resume(at: s(9)))
        #expect(inversionAsked(drill) == "Root position")
    }

    @Test func aChimeHoldsItWithoutLosingNotes() {
        var drill = aMinor()
        play(52, at: 1, &drill)
        #expect(drill.canHold)
        drill.handle(.hold(until: s(4)))
        #expect(drill.display?.chips.map(\.text) == ["E", "?", "?"])
        drill.handle(.tick(at: s(4)))
        play(57, at: 5, &drill)
        #expect(drill.attempts.last?.responseTime == s(1))
    }

    @Test func startingAgainForgetsTheClimb() {
        var drill = aMinor()
        play(second, from: 1, &drill)
        drill.handle(.stop(at: s(4)))
        drill.handle(.start(at: s(5)))
        #expect(drill.attempts.isEmpty)
        #expect(drill.display?.voicings.map(\.state).first == .current)
        #expect(drill.prompt?.target?.string == 2)
    }
}

@Suite("Climbs")
struct ClimbTests {
    private struct Step {
        let facts: TriadFacts
        let bass: FretboardLocation
    }

    /// The voicings of the first climbs of a run, each skipped, in the order they were asked for.
    private func climbs(_ setup: DrillSetup, count: Int) -> [[Step]] {
        var drill = DrillKind.inversions.makeDrill(setup)
        drill.handle(.start(at: s(0)))
        while (drill.attempts.last?.group?.number ?? 0) < count { drill.handle(.skip(at: s(1))) }
        return (0..<count).map { number in
            drill.attempts.filter { $0.group?.number == number }.compactMap { attempt in
                guard case .triad(let facts) = attempt.facts, let bass = attempt.prompt.target else { return nil }
                return Step(facts: facts, bass: bass)
            }
        }
    }

    @Test(arguments: [TuningPreset.standard, .dropD, .dadgad, .openG], [0, 5])
    func eachIsEveryVoicingInRangeUpAndBack(_ preset: TuningPreset, _ capo: Int) {
        let setup = setup(preset, capo: capo) { $0.frets = 0...22 }
        let climbs = climbs(setup, count: 60)
        for climb in climbs {
            let frets = climb.map(\.bass.fret)
            let top = climb.count / 2
            #expect(climb.count % 2 == 1 && climb.count >= 3)
            #expect(frets == frets.reversed())
            #expect(zip(frets.prefix(top), frets.dropFirst()).allSatisfy { $0 < $1 })
            let facts = climb[0].facts
            let inRange = Triad.Inversion.allCases.flatMap {
                setup.fretboard.voicings(of: facts.triad, inversion: $0, on: facts.stringSet, frets: 0...22)
            }
            #expect(Set(climb.map(\.bass)) == Set(inRange.map { $0.locations[0] }))
            #expect(top + 1 == inRange.count)
            #expect(climb.allSatisfy { $0.facts.triad == facts.triad && $0.facts.stringSet == facts.stringSet })
        }
        #expect(zip(climbs, climbs.dropFirst()).allSatisfy {
            $0[0].facts.triad != $1[0].facts.triad || $0[0].facts.stringSet != $1[0].facts.stringSet
        })
    }

    @Test func theInversionsOptionIsIgnoredAndTheSetsAreNot() {
        let climbs = climbs(setup {
            $0.inversions = [.root]
            $0.stringSets = [.gBE]
        }, count: 20)
        #expect(Set(climbs.joined().map(\.facts.inversion)) == Set(Triad.Inversion.allCases))
        #expect(Set(climbs.joined().map(\.facts.stringSet)) == [.gBE])
    }

    @Test func aChordWithOneVoicingInRangeIsNotAsked() {
        // A minor is only at 2 2 1 (7 5 5 is past the range); G major is at 0 0 0 and 5 4 3.
        let asked = climbs(setup {
            $0.frets = 0...6
            $0.stringSets = [.dGB]
        }, count: 100)
        let chords = Set(asked.map { $0[0].facts.triad.name })
        #expect(chords.contains("G major"))
        #expect(!chords.contains("A minor"))
    }

    @Test func noChordWithTwoVoicingsIsAReasonNotToStart() {
        // Only G major, and only at 12 12 12.
        let none = DrillKind.inversions.makeDrill(setup(capo: 12) { $0.stringSets = [.dGB] })
        #expect(none.nothingToPromptReason == "No chord of the key has two voicings in these frets and string sets.")
        #expect(DrillKind.inversions.makeDrill(setup()).nothingToPromptReason == nil)
    }

    /// E minor on D A D: only the 1st inversion fits a hand, at 5 2 2 and 17 14 14.
    @Test func dropD() {
        var drill = climbing(Triad(.minor, root: .e), on: .eAD, in: .dropD, frets: 0...22)
        #expect(drill.display?.voicings.map(\.title) == ["1st", "1st", "1st"])
        play([43, 47, 52], from: 1, &drill)
        play([55, 59, 64], from: 4, &drill)
        #expect(drill.attempts.map { $0.location?.fret } == [5, 2, 2, 17, 14, 14])
        #expect(drill.attempts.allSatisfy { $0.firstRight })
    }

    /// G major on G B D: the open strings, 4 3 5, 7 8 9 and 12 12 12.
    @Test func openG() {
        let drill = climbing(Triad(.major, root: .g), on: .gBE, in: .openG)
        #expect(drill.display?.voicings.map(\.title) == ["root", "1st", "2nd", "root", "2nd", "1st", "root"])
    }
}
