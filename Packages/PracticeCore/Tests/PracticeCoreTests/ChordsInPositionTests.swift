import Testing
import PracticeCore
import TheoryCore

/// I–V–vi–IV in G, in the E shape, as in `ProgressionRun`. Chords in position has no clock of its own, so each chord
/// here is played 2 s after the one before, and a tick moves it on.
extension ProgressionRun {
    /// The chord's voicing with these frets, its notes 0.3 s apart from `time`, then a tick once it has moved on.
    mutating func play(_ chord: Int, _ frets: [Int], at time: Double) {
        play(voicing(chord, frets), from: time)
        tick(time + 1.2)
    }

    /// Each chord, low to high, once round, from `time`, 2 s apart.
    mutating func playRound(_ frets: [[Int]], from time: Double) {
        for (chord, frets) in frets.enumerated() { play(chord, frets, at: time + 2 * Double(chord)) }
    }
}

/// The voicing's shape at a fade level, as if the triad drills had taken it there.
private func reached(_ voicing: TriadVoicing, level: Int) -> FadeLevels {
    var reached = FadeLevels()
    let shape = FadeLevels.VoicingShape(tuning: .standard, quality: voicing.triad.quality, inversion: voicing.inversion,
                                        stringSet: voicing.stringSet)
    for number in 0..<level {
        reached.add(voicing: (0..<3).map {
            FadeLevels.VoicingNote(shape: shape, level: FadeLevel(number), hinted: false, place: $0, outcome: .answered,
                                   firstRight: true)
        })
    }
    return reached
}

@Suite("Chords in position")
struct ChordsInPositionTests {
    /// Stay in position's voicings for the first two times through.
    static let first: [[Int]] = [[4, 3, 3], [2, 3, 2], [3, 2, 2], [3, 3, 2]]
    static let second: [[Int]] = [[5, 4, 3], [4, 2, 3], [4, 5, 3], [5, 5, 3]]

    @Test func expectsStayInPositionsVoicingsAndEndsOnceEachChordIsCleanTwice() {
        var run = ProgressionRun(.chordsInPosition)
        run.start()
        run.playRound(Self.first, from: 0.5)
        #expect(run.drill.isRunning)
        run.playRound(Self.second, from: 8.5)
        let accepted = run.chordFacts.map { $0.accepted.map { $0.locations.map(\.fret) } }
        #expect(accepted == (Self.first + Self.second).map { [$0] })
        #expect(run.chordFacts.allSatisfy { $0.outcome == .clean })
        #expect(!run.drill.isRunning)
    }

    @Test func aChordThatIsntCleanIsAskedForAgainNextTimeThroughInItsNextVoicing() {
        var run = ProgressionRun(.chordsInPosition)
        run.start()
        // A wrong note before G, then G as shown: not clean.
        run.drill.handle(.played(Pitch(41), onset: s(0.2), at: s(0.25)))
        run.playRound(Self.first, from: 0.5)
        run.playRound(Self.second, from: 8.5)
        #expect(run.chordFacts.map(\.outcome) == [.wrong, .clean, .clean, .clean, .clean, .clean, .clean, .clean])
        #expect(run.drill.isRunning)
        // The third time through starts with G's third voicing, and once it is clean the run ends.
        run.play(0, [5, 5, 4], at: 16.5)
        #expect(run.chordFacts.last?.outcome == .clean)
        #expect(run.chordFacts.count == 9)
        #expect(!run.drill.isRunning)
    }

    @Test func isUntimed() {
        var run = ProgressionRun(.chordsInPosition)
        run.start()
        run.tick(60)
        #expect(run.drill.attempts.isEmpty)
        #expect(run.drill.timeRemaining(at: s(60)) == nil)
        #expect(run.drill.display?.headline == "G")
        run.play(0, [4, 3, 3], at: 60)
        #expect(run.chordFacts.map(\.outcome) == [.clean])
        #expect(run.drill.display?.headline == "D")
    }

    @Test func afterThreeMinutesItEndsOnceTheChordThatIsUpIsDone() {
        var run = ProgressionRun(.chordsInPosition)
        run.start()
        run.play(0, [4, 3, 3], at: 0.5)
        // D is up from 1.7 s; 3 minutes pass, and it still waits.
        run.tick(200)
        #expect(run.drill.isRunning)
        run.play(1, [2, 3, 2], at: 200)
        #expect(run.chordFacts.count == 2)
        #expect(!run.drill.isRunning)
    }

    @Test func pausedTimeDoesntCountTowardsTheThreeMinutes() {
        var run = ProgressionRun(.chordsInPosition)
        run.start()
        run.drill.handle(.pause(at: s(100)))
        run.drill.handle(.resume(at: s(1000)))
        run.play(0, [4, 3, 3], at: 1000)
        #expect(run.drill.isRunning)
        #expect(run.drill.display?.headline == "D")
    }

    @Test func resumeBringsTheChordUpAgainFromItsFirstNote() {
        var run = ProgressionRun(.chordsInPosition)
        run.start()
        let g = run.fretboard.locationsLowToHigh(of: run.voicing(0, [4, 3, 3]))
        run.drill.handle(.played(run.fretboard.pitch(at: g[0]), onset: s(1), at: s(1.05)))
        run.drill.handle(.pause(at: s(2)))
        #expect(run.drill.display == nil)
        run.drill.handle(.resume(at: s(10)))
        #expect(run.drill.prompt?.target == g[0])
        run.play(0, [4, 3, 3], at: 10.5)
        #expect(run.chordFacts.map(\.outcome) == [.clean])
    }

    @Test func skipScoresTheChordAsMissedAndMovesOn() {
        var run = ProgressionRun(.chordsInPosition)
        run.start()
        run.drill.handle(.skip(at: s(3)))
        #expect(run.drill.attempts.map(\.outcome) == [.skipped])
        #expect(run.chordFacts.map(\.outcome) == [.missed])
        #expect(run.chordFacts.first?.played == nil)
        #expect(run.drill.display?.headline == "D")
    }

    @Test func aWrongNoteLeavesTheNextNoteToPlayAndTheLowestStartsAgain() throws {
        var run = ProgressionRun(.chordsInPosition)
        run.start()
        let g = run.voicing(0, [4, 3, 3])
        let pitches = run.fretboard.pitches(of: g)
        run.drill.handle(.played(pitches[0], onset: s(1), at: s(1.05)))
        run.drill.handle(.played(Pitch(41), onset: s(1.5), at: s(1.55)))
        #expect(run.drill.display?.feedback == "You played F")
        #expect(run.drill.prompt?.target == run.fretboard.locationsLowToHigh(of: g)[1])
        run.drill.handle(.played(pitches[0], onset: s(2), at: s(2.05)))
        run.drill.handle(.played(pitches[1], onset: s(2.5), at: s(2.55)))
        run.drill.handle(.played(pitches[2], onset: s(3), at: s(3.05)))
        let facts = try #require(run.chordFacts.first)
        #expect(facts.outcome == .wrong)
        #expect(facts.played == g)
        #expect(run.drill.display?.feedback == "Not clean")
    }

    @Test func attemptsRecordTheVoicingsLevelAndNoBacking() {
        let g = ProgressionRun(.chordsInPosition).voicing(0, [4, 3, 3])
        var run = ProgressionRun(.chordsInPosition, fadeLevels: reached(g, level: 2))
        run.start()
        run.playRound(Self.first, from: 0.5)
        let facts = run.chordFacts
        #expect(facts.map(\.fadeLevel) == [FadeLevel(2), .first, .first, .first])
        #expect(facts.allSatisfy { $0.style == nil && $0.tempo == nil })
        #expect(run.drill.attempts.map(\.group) == (0..<4).map { AttemptGroup(number: 0, size: 4, place: $0) })
        #expect(facts.first?.firstOnset == s(0.5))
        // Chords don't move the levels.
        #expect(run.drill.fadeLevels?.level(of: FadeLevels.VoicingShape(
            tuning: .standard, quality: .major, inversion: g.inversion, stringSet: g.stringSet)) == FadeLevel(2))
    }

    @Test func theVoicingFadesAtItsLevelOverTenSecondsFromWhenItComesUp() throws {
        let g = ProgressionRun(.chordsInPosition).voicing(0, [4, 3, 3])
        var run = ProgressionRun(.chordsInPosition, fadeLevels: reached(g, level: 1))
        run.start()
        run.tick(4.5)
        // Level 1 fades over 90 % of 10 s: half gone at 4.5 s.
        let markers = try #require(run.drill.display?.markers)
        #expect(markers.filter(\.isAnswer).map(\.opacity) == [1])
        #expect(markers.filter { !$0.isAnswer }.map(\.opacity) == [0.5, 0.5])
        #expect(run.drill.display?.subline == "I · E shape · 1st time through · Level 1")
        run.tick(9)
        #expect(run.drill.display?.markers.count == 1)
    }

    @Test func holdingHShowsTheVoicingAndTheChordIsntClean() {
        let g = ProgressionRun(.chordsInPosition).voicing(0, [4, 3, 3])
        var run = ProgressionRun(.chordsInPosition, fadeLevels: reached(g, level: 6))
        run.start()
        #expect(run.drill.display?.markers.count == 1)
        run.drill.handle(.hint(isShown: true, at: s(1)))
        #expect(run.drill.display?.markers.count == 3)
        run.drill.handle(.hint(isShown: false, at: s(2)))
        run.play(0, [4, 3, 3], at: 3)
        #expect(run.chordFacts.first?.outcome == .wrong)
        #expect(run.chordFacts.first?.hinted == true)
    }

    @Test func eachChordHasAChipDoneOnceCleanTwice() throws {
        var run = ProgressionRun(.chordsInPosition)
        run.start()
        run.playRound(Self.first, from: 0.5)
        run.play(0, [5, 4, 3], at: 8.5)
        let chips = try #require(run.drill.display?.chips)
        #expect(chips.map(\.text) == ["G", "D", "Em", "C"])
        #expect(chips.map(\.title) == ["I", "V", "vi", "IV"])
        #expect(chips.map(\.state) == [.found, .current, .waiting, .waiting])
    }

    @Test func hasNothingToAskWithoutAProgression() {
        var options = DrillOptions()
        options.key = .major(.g)
        let drill = DrillKind.chordsInPosition.makeDrill(DrillSetup(fretboard: Fretboard(tuning: .standard), options: options, seed: 1))
        #expect(drill.nothingToPromptReason == "Choose a progression.")
    }
}
