import Testing
import PracticeCore
import TheoryCore

/// I–V–vi–IV in G, G major's E shape (frets 2–5), at 60 BPM: a beat a second, a bar four. The count-in is 0–4 s, then
/// G 4–8, D 8–12, Em 12–16 and C 16–20; the second time through starts at 20.
private struct Run {
    let fretboard = Fretboard(tuning: .standard)
    var drill: any Drill
    let progression = Progression.named("I–V–vi–IV")!
    let key = Key.major(.g)

    init(inputDelay: Duration = .zero, tuning: Tuning = .standard) {
        var options = DrillOptions()
        options.key = .major(.g)
        options.progression = Progression.named("I–V–vi–IV")
        options.position = Position.ID(system: .caged, number: CAGEDShape.e.number)
        options.backing = BackingSettings(tempo: 60, inputDelay: inputDelay)
        drill = DrillKind.nearestVoicing.makeDrill(DrillSetup(fretboard: Fretboard(tuning: tuning), options: options, seed: 1))
    }

    var position: Position { drill.setup.progressionPosition! }
    var chords: [Triad] { progression.chords(in: key) }

    func voicings(_ chord: Int) -> [TriadVoicing] { fretboard.voicings(of: chords[chord], in: position) }

    func pitches(_ voicing: TriadVoicing) -> [Pitch] { voicing.locations.map(fretboard.pitch) }

    mutating func start() {
        drill.handle(.start(at: s(0)))
    }

    /// Notes at their onsets, each heard 50 ms later.
    mutating func play(_ pitches: [Int], at onsets: [Double]) {
        for (pitch, onset) in zip(pitches, onsets) {
            drill.handle(.played(Pitch(pitch), onset: s(onset), at: s(onset + 0.05)))
        }
    }

    mutating func play(_ voicing: TriadVoicing, from onset: Double) {
        play(pitches(voicing).map(\.midi), at: [onset, onset + 0.3, onset + 0.6])
    }

    mutating func tick(_ time: Double) { drill.handle(.tick(at: s(time))) }

    var chordFacts: [ChordFacts] { drill.attempts.compactMap(\.chord) }
}

/// G D B on string 4 fret 5, string 3 fret 4, string 2 fret 3: the middle of the E shape.
private let gOnDGB = [55, 59, 62]

@Suite("Nearest voicing: scoring")
struct NearestVoicingScoringTests {
    @Test func anyVoicingInThePositionIsCleanForTheFirstChord() {
        for index in 0..<3 {
            var run = Run()
            run.start()
            let voicing = run.voicings(0)[index]
            run.play(voicing, from: 4)
            run.tick(8.3)
            let facts = run.chordFacts
            #expect(facts.count == 1)
            #expect(facts.first?.outcome == .clean)
            #expect(facts.first?.played == voicing)
            #expect(facts.first?.accepted == run.voicings(0))
        }
    }

    @Test func theNextChordAcceptsTheNearestToTheOnePlayed() {
        var run = Run()
        run.start()
        run.play(gOnDGB, at: [4, 4.4, 4.8])
        // D F♯ A on string 4 fret 4, string 3 fret 2, string 2 fret 3: 3 semitones away.
        run.play([54, 57, 62], at: [8, 8.4, 8.8])
        run.tick(12.3)
        let d = run.chordFacts[1]
        #expect(d.outcome == .clean)
        #expect(d.accepted.map { $0.locations.map(\.fret) } == [[4, 2, 3]])
    }

    @Test func anotherVoicingOfTheRightChordIsWrongAndTheNextFollowsIt() throws {
        var run = Run()
        run.start()
        run.play(gOnDGB, at: [4, 4.4, 4.8])
        // D on E-A-D, frets 5 5 4: in the position, but not the nearest.
        run.play([45, 50, 54], at: [8, 8.4, 8.8])
        run.tick(16.3)
        let d = run.chordFacts[1], em = run.chordFacts[2]
        #expect(d.outcome == .wrong)
        let played = try #require(d.played)
        #expect(played.stringSet == .eAD)
        #expect(em.accepted == run.fretboard.nearestVoicings(of: run.chords[2], in: run.position, to: played))
        #expect(em.outcome == .missed)
    }

    @Test func aWrongPitchMakesTheChordWrong() {
        var run = Run()
        run.start()
        run.play([55, 60, 59, 62], at: [4, 4.4, 4.8, 5.2])
        run.tick(8.3)
        #expect(run.chordFacts.first?.outcome == .wrong)
        #expect(run.drill.attempts.first?.wrongAnswers == [.pitch(Pitch(60))])
    }

    @Test func aWrongNoteBeforeTheVoicingStillMakesItWrong() {
        var run = Run()
        run.start()
        run.play([52, 55, 59, 62], at: [4, 4.4, 4.8, 5.2])
        run.tick(8.3)
        #expect(run.chordFacts.first?.outcome == .wrong)
        #expect(run.chordFacts.first?.played?.locations.map(\.fret) == [5, 4, 3])
    }

    @Test func notAllThreeNotesIsMissedAndTheNextAcceptsAny() {
        var run = Run()
        run.start()
        run.play(gOnDGB, at: [4, 4.4, 4.8])
        run.play([54, 57], at: [8, 8.4])
        run.tick(12.3)
        let d = run.chordFacts[1]
        #expect(d.outcome == .missed)
        #expect(d.played == nil)
        run.tick(16.3)
        #expect(run.chordFacts[2].accepted == run.voicings(2))
    }

    @Test func nothingPlayedIsMissedWithNoOnset() {
        var run = Run()
        run.start()
        run.tick(8.3)
        #expect(run.chordFacts.first?.outcome == .missed)
        #expect(run.chordFacts.first?.firstOnset == nil)
        #expect(run.drill.attempts.first?.outcome == .timedOut)
    }

    @Test func upToHalfABeatEarlyCounts() {
        var run = Run()
        run.start()
        run.play(gOnDGB, at: [3.6, 4.2, 4.6])
        run.tick(8.3)
        #expect(run.chordFacts.first?.outcome == .clean)
        #expect(run.chordFacts.first?.firstOnset == s(-0.4))
    }

    @Test func earlierThanThatIsIgnored() {
        var run = Run()
        run.start()
        run.play([55], at: [3.4])
        run.tick(8.3)
        #expect(run.chordFacts.first?.outcome == .missed)
        #expect(run.chordFacts.first?.firstOnset == nil)
    }

    @Test func notesAfterAFinishedVoicingAreIgnoredUntilTheNextWindow() {
        var run = Run()
        run.start()
        run.play(gOnDGB + [67, 50, 62], at: [4, 4.4, 4.8, 5.5, 6, 7])
        // Half a beat early for D.
        run.play([54, 57, 62], at: [7.6, 8.2, 8.6])
        run.tick(12.3)
        #expect(run.chordFacts.map(\.outcome) == [.clean, .clean])
    }

    @Test func aVoicingCanFinishInTheHalfBeatBeforeTheNextChord() {
        var run = Run()
        run.start()
        run.play(gOnDGB, at: [6.5, 7.2, 7.7])
        run.tick(8.3)
        #expect(run.chordFacts.first?.outcome == .clean)
    }

    @Test func aNotePlayedAgainAtOnceIsIgnored() {
        var run = Run()
        run.start()
        run.play([55, 55, 59, 59, 62], at: [4, 4.2, 4.4, 4.6, 4.8])
        run.tick(8.3)
        #expect(run.chordFacts.first?.outcome == .clean)
    }

    @Test func theInputDelayIsTakenOffOnsetsAndRecorded() {
        var run = Run(inputDelay: .milliseconds(300))
        run.start()
        // Heard 3.75 is played at 3.45: too early.
        run.play([55], at: [3.75])
        run.play([59, 62], at: [4.3, 4.6])
        run.tick(8.3)
        #expect(run.chordFacts.first?.outcome == .missed)
        #expect(run.chordFacts.first?.inputDelay == .milliseconds(300))

        var late = Run(inputDelay: .milliseconds(300))
        late.start()
        late.play(gOnDGB, at: [4.3, 4.6, 4.9])
        late.tick(8.3)
        #expect(late.chordFacts.first?.firstOnset == .zero)
    }

    @Test func eachChordIsOneAttemptGroupedByTimeThrough() {
        var run = Run()
        run.start()
        run.tick(24.3)
        let groups = run.drill.attempts.map(\.group)
        #expect(groups.map { $0?.size } == [4, 4, 4, 4, 4])
        #expect(groups.map { $0?.place } == [0, 1, 2, 3, 0])
        #expect(Set(groups.prefix(4).map { $0?.number }).count == 1)
        #expect(groups[4]?.number != groups[0]?.number)
        #expect(run.chordFacts.map(\.triad.shortName) == ["G", "D", "Em", "C", "G"])
        #expect(run.chordFacts.allSatisfy { $0.style == .rock && $0.tempo == 60 && $0.key == .major(.g) })
    }
}

@Suite("Nearest voicing: fade, keys and backing")
struct NearestVoicingRunTests {
    /// Plays every chord of a time through in its drawn voicing, but `wrong` ones as a wrong pitch.
    private func playTimeThrough(_ run: inout Run, from start: Double, after previous: inout TriadVoicing?,
                                 wrong: Set<Int> = []) {
        for index in 0..<4 {
            let voicing = previous.flatMap {
                run.fretboard.nearestVoicings(of: run.chords[index], in: run.position, to: $0).first
            } ?? run.fretboard.middleVoicing(of: run.chords[index], in: run.position)!
            let onset = start + Double(index) * 4
            if wrong.contains(index) {
                run.play([30], at: [onset])
                previous = nil
            } else {
                run.play(voicing, from: onset)
                previous = voicing
            }
        }
    }

    @Test func shownForTwoTimesThroughFadedForTwoThenHidden() {
        var run = Run()
        run.start()
        var previous: TriadVoicing?
        for index in 0..<5 { playTimeThrough(&run, from: 4 + Double(index) * 16, after: &previous) }
        run.tick(84.3)
        let stages = run.chordFacts.map(\.fadeStage)
        #expect(stages.count == 20)
        #expect(stages == Array(repeating: .shown, count: 8) + Array(repeating: .faded, count: 8)
                + Array(repeating: .hidden, count: 4))
        #expect(run.chordFacts.allSatisfy { $0.outcome == .clean })
    }

    @Test func aHiddenTimeThroughThatIsntCleanBringsBackOneFaded() {
        var run = Run()
        run.start()
        var previous: TriadVoicing?
        for index in 0..<7 {
            playTimeThrough(&run, from: 4 + Double(index) * 16, after: &previous, wrong: index == 4 ? [2] : [])
        }
        run.tick(116.3)
        let byTimeThrough = stride(from: 0, to: 28, by: 4).map { run.chordFacts[$0].fadeStage }
        #expect(byTimeThrough == [.shown, .shown, .faded, .faded, .hidden, .faded, .hidden])
    }

    @Test func holdingHShowsTheVoicingAndTheChordIsntClean() throws {
        var run = Run()
        run.start()
        var previous: TriadVoicing?
        for index in 0..<4 { playTimeThrough(&run, from: 4 + Double(index) * 16, after: &previous) }
        run.tick(68.3)
        #expect(run.drill.display?.markers.isEmpty == true)
        run.drill.handle(.hint(isShown: true, at: s(69)))
        #expect(run.drill.display?.markers.count == 3)
        run.drill.handle(.hint(isShown: false, at: s(69.5)))
        playTimeThrough(&run, from: 68, after: &previous)
        run.tick(84.3)
        let g = try #require(run.chordFacts.dropFirst(16).first)
        #expect(g.outcome == .wrong)
        #expect(g.hinted)
        #expect(run.chordFacts.dropFirst(17).allSatisfy { $0.outcome == .clean && !$0.hinted })
    }

    @Test func startAsksForTheBackingLoopedFromACountIn() throws {
        var run = Run()
        run.start()
        let requests = run.drill.takeBacking()
        guard case .start(let backing) = try #require(requests.first) else { Issue.record("no backing"); return }
        #expect(backing.start == s(0))
        #expect(backing.bpm == 60)
        #expect(backing.style == .rock)
        #expect(backing.chords.map(\.triad) == run.chords)
        #expect(run.drill.takeBacking().isEmpty)
    }

    @Test func theBackingAsHeardMovesTheWindows() {
        var run = Run()
        run.start()
        _ = run.drill.takeBacking()
        let heard = Backing(chords: run.chords.map { BackingChord($0) }, style: .rock, bpm: 60, start: s(1))
        run.drill.handle(.backingStarted(heard))
        run.play(gOnDGB, at: [5, 5.4, 5.8])
        run.tick(9.3)
        #expect(run.chordFacts.first?.outcome == .clean)
        #expect(run.chordFacts.first?.firstOnset == .zero)
    }

    @Test func pausingStopsTheBackingAndResumeStartsTheTimeThroughAgain() throws {
        var run = Run()
        run.start()
        _ = run.drill.takeBacking()
        run.play(gOnDGB, at: [4, 4.4, 4.8])
        run.play([54], at: [8])
        run.drill.handle(.pause(at: s(9)))
        #expect(run.drill.takeBacking() == [.stop])
        #expect(run.drill.phase == .paused)
        #expect(run.drill.display == nil)
        #expect(run.chordFacts.count == 1)

        run.drill.handle(.resume(at: s(30)))
        guard case .start(let backing) = try #require(run.drill.takeBacking().first) else {
            Issue.record("no backing"); return
        }
        #expect(backing.start == s(30))
        run.tick(31)
        #expect(run.drill.display?.progression?.countIn == 2)
        #expect(run.drill.display?.progression?.timeThrough == 1)
        // The first chord accepts any voicing again.
        run.play([59, 62, 67], at: [34, 34.4, 34.8])
        run.tick(38.3)
        #expect(run.chordFacts.count == 2)
        #expect(run.chordFacts[1].outcome == .clean)
        #expect(run.drill.attempts[1].group?.number != run.drill.attempts[0].group?.number)
    }

    @Test func skipDoesNothing() {
        var run = Run()
        run.start()
        run.drill.handle(.skip(at: s(5)))
        #expect(run.drill.attempts.isEmpty)
        #expect(run.drill.phase == .waiting)
    }

    @Test func stopStopsTheBacking() {
        var run = Run()
        run.start()
        _ = run.drill.takeBacking()
        run.drill.handle(.stop(at: s(5)))
        #expect(run.drill.takeBacking() == [.stop])
        #expect(!run.drill.isRunning)
    }
}

@Suite("Nearest voicing: display")
struct NearestVoicingDisplayTests {
    @Test func theCountInCountsAndTheMiddleVoicingIsShownWithTheNextGhosted() throws {
        var run = Run()
        run.start()
        run.tick(2.5)
        let display = try #require(run.drill.display)
        let progress = try #require(display.progression)
        #expect(progress.countIn == 3)
        #expect(progress.current == nil)
        #expect(progress.blocks.map(\.name) == ["G", "D", "Em", "C"])
        #expect(progress.blocks.map(\.numeral) == ["I", "V", "vi", "IV"])
        #expect(progress.timeThroughText == "1st time through · Shown")
        let solid = display.markers.filter { !$0.isFaint }
        #expect(solid.map(\.location.fret) == [5, 4, 3])
        #expect(solid.map(\.label) == ["G", "B", "D"])
        // D on D-G-B, frets 4 2 3, ghosted; its D on string 2 fret 3 is shared.
        #expect(Set(display.markers.filter(\.isFaint).map(\.location)) == [
            FretboardLocation(string: 2, fret: 4), FretboardLocation(string: 3, fret: 2),
        ])
        #expect(display.highlightedStrings == [2, 3, 4])
    }

    @Test func notesPlayedAreSolidAndTheLastRinged() throws {
        var run = Run()
        run.start()
        run.play([55, 59], at: [4, 4.4])
        let markers = try #require(run.drill.display?.markers.filter { !$0.isFaint })
        #expect(markers.filter(\.isLastPlayed).map(\.location) == [FretboardLocation(string: 3, fret: 4)])
    }

    @Test func pastChordsAreColouredByOutcomeAndThePlayheadMoves() throws {
        var run = Run()
        run.start()
        run.play(gOnDGB, at: [4, 4.4, 4.8])
        run.play([54, 60], at: [8, 8.4])
        run.tick(13)
        let progress = try #require(run.drill.display?.progression)
        #expect(progress.blocks.map(\.outcome) == [.clean, .wrong, nil, nil])
        #expect(progress.current == 2)
        #expect(abs(progress.beat - 9) < 0.01)
    }

    @Test func theNeckMovesToTheNextChordHalfABeatEarly() throws {
        var run = Run()
        run.start()
        run.play(gOnDGB, at: [4, 4.4, 4.8])
        run.tick(7.6)
        let solid = try #require(run.drill.display?.markers.filter { !$0.isFaint })
        #expect(solid.map(\.location.fret) == [4, 2, 3])
    }

    @Test func aNothingToPromptReasonWithoutAProgressionOrAVoicing() {
        var setup = DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1)
        #expect(DrillKind.nearestVoicing.makeDrill(setup).nothingToPromptReason == "Choose a progression.")
        setup.options.progression = Progression.named("I–V–vi–IV")
        #expect(DrillKind.nearestVoicing.makeDrill(setup).nothingToPromptReason == nil)

        // Somewhere in DADGAD, a progression has a chord with no voicing in the position.
        let dadgad = Fretboard(tuning: TuningPreset.dadgad.tuning)
        var found: String?
        search: for key in Key.appMajorKeys + Key.appMinorKeys {
            for position in dadgad.cagedPositions(of: key.scale) {
                for progression in Progression.library(key.mode) where !dadgad.fits(progression, in: key, position: position) {
                    var options = DrillOptions()
                    (options.key, options.progression, options.position) = (key, progression, position.id)
                    found = DrillKind.nearestVoicing.makeDrill(DrillSetup(fretboard: dadgad, options: options, seed: 1))
                        .nothingToPromptReason
                    break search
                }
            }
        }
        #expect(found?.contains("no voicing in the") == true)
    }
}
