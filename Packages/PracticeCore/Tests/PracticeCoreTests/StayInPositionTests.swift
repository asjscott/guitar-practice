import Testing
import PracticeCore
import TheoryCore

/// I–V–vi–IV in G, G major's E shape (frets 2–5), at 60 BPM: the count-in is 0–4 s, then G 4–8, D 8–12, Em 12–16 and
/// C 16–20; each time through is 16 s. The chords' voicings in the position, up the neck, as frets low to high:
/// G [4 3 3] [5 4 3] [5 5 4]; D [2 3 2] [4 2 3] [5 4 2] [5 5 4]; Em [3 2 2] [4 5 3] [5 4 5]; C [3 3 2] [5 5 3] [5 5 5].
struct ProgressionRun {
    let fretboard = Fretboard(tuning: .standard)
    var drill: any Drill
    let progression = Progression.named("I–V–vi–IV")!
    let key = Key.major(.g)

    init(_ kind: DrillKind) {
        var options = DrillOptions()
        options.key = key
        options.progression = progression
        options.position = Position.ID(system: .caged, number: CAGEDShape.e.number)
        options.backing = BackingSettings(tempo: 60)
        drill = kind.makeDrill(DrillSetup(fretboard: fretboard, options: options, seed: 1))
    }

    var position: Position { drill.setup.progressionPosition! }
    var chords: [Triad] { progression.chords(in: key) }

    /// The chord's voicing in the position with these frets, low to high.
    func voicing(_ chord: Int, _ frets: [Int]) -> TriadVoicing {
        fretboard.voicings(of: chords[chord], in: position).first { $0.locations.map(\.fret) == frets }!
    }

    mutating func start() { drill.handle(.start(at: s(0))) }

    /// The voicing's notes from `onset`, 0.3 s apart, each heard 50 ms later.
    mutating func play(_ voicing: TriadVoicing, from onset: Double) {
        for (index, location) in voicing.locations.enumerated() {
            let time = onset + 0.3 * Double(index)
            drill.handle(.played(fretboard.pitch(at: location), onset: s(time), at: s(time + 0.05)))
        }
    }

    /// The chord's voicing with these frets, played on the chord's first beat in a time through (from 0).
    mutating func play(_ chord: Int, _ frets: [Int], timeThrough: Int = 0) {
        play(voicing(chord, frets), from: 4 + 16 * Double(timeThrough) + 4 * Double(chord))
    }

    mutating func tick(_ time: Double) { drill.handle(.tick(at: s(time))) }

    var chordFacts: [ChordFacts] { drill.attempts.compactMap(\.chord) }
}

@Suite("Stay in position")
struct StayInPositionTests {
    @Test func eachTimeThroughExpectsEachChordsNextVoicingUpTheNeckWrappingPerChord() {
        var run = ProgressionRun(.stayInPosition)
        run.start()
        run.tick(4 + 16 * 4 + 0.3)
        let accepted = run.chordFacts.map { $0.accepted.map { $0.locations.map(\.fret) } }
        #expect(accepted.count == 16)
        #expect(accepted.allSatisfy { $0.count == 1 })
        #expect(accepted.map { $0[0] } == [
            [4, 3, 3], [2, 3, 2], [3, 2, 2], [3, 3, 2],
            [5, 4, 3], [4, 2, 3], [4, 5, 3], [5, 5, 3],
            [5, 5, 4], [5, 4, 2], [5, 4, 5], [5, 5, 5],
            // G and Em and C have three, so they wrap; D has a fourth.
            [4, 3, 3], [5, 5, 4], [3, 2, 2], [3, 3, 2],
        ])
    }

    @Test func theExpectedVoicingIsCleanAndAnotherInThePositionIsWrong() {
        var run = ProgressionRun(.stayInPosition)
        run.start()
        run.play(0, [4, 3, 3])
        run.play(1, [4, 2, 3])
        run.tick(12.3)
        #expect(run.chordFacts.map(\.outcome) == [.clean, .wrong])
        #expect(run.chordFacts[1].played == run.voicing(1, [4, 2, 3]))
    }

    @Test func theSecondTimeThroughMovesOnWhateverWasPlayed() {
        var run = ProgressionRun(.stayInPosition)
        run.start()
        run.play(0, [5, 4, 3], timeThrough: 0)
        run.play(0, [5, 4, 3], timeThrough: 1)
        run.tick(24.3)
        #expect(run.chordFacts.first?.outcome == .wrong)
        #expect(run.chordFacts.last?.outcome == .clean)
    }

    @Test func theNeckDrawsTheExpectedVoicing() throws {
        var run = ProgressionRun(.stayInPosition)
        run.start()
        run.tick(20.5)
        let display = try #require(run.drill.display)
        #expect(display.progression?.timeThrough == 2)
        let current = Set(display.markers.filter { !$0.isFaint }.map(\.location))
        #expect(current == Set(run.voicing(0, [5, 4, 3]).locations))
        #expect(display.progression?.topNotes == nil)
    }

    @Test func resumeStartsTheSameTimeThroughAgainWithTheSameVoicings() {
        var run = ProgressionRun(.stayInPosition)
        run.start()
        run.tick(21)
        run.drill.handle(.pause(at: s(21)))
        run.drill.handle(.resume(at: s(40)))
        // The count-in is 40–44; G is 44–48.
        run.play(run.voicing(0, [5, 4, 3]), from: 44)
        run.tick(48.3)
        #expect(run.chordFacts.last?.outcome == .clean)
        #expect(run.drill.display?.progression?.timeThrough == 2)
    }
}
