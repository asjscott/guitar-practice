import Testing
import PracticeCore
import TheoryCore

@Suite("Chord run summary")
struct ChordRunSummaryTests {
    /// Plays the drawn path of I–V–vi–IV in G, E shape, 60 BPM, `timesThrough` times, with D wrong in the 5th.
    private func run(timesThrough: Int) -> [Attempt] {
        var options = DrillOptions()
        options.key = .major(.g)
        options.progression = Progression.named("I–V–vi–IV")
        options.backing = BackingSettings(tempo: 60)
        let fretboard = Fretboard(tuning: .standard)
        var drill = DrillKind.nearestVoicing.makeDrill(DrillSetup(fretboard: fretboard, options: options, seed: 1))
        let position = drill.setup.progressionPosition!
        let chords = options.progression!.chords(in: .major(.g))
        drill.handle(.start(at: s(0)))
        var previous: TriadVoicing?
        for pass in 0..<timesThrough {
            for index in 0..<4 {
                let onset = 4 + Double(pass * 16 + index * 4)
                let voicing = previous.flatMap { fretboard.nearestVoicings(of: chords[index], in: position, to: $0).first }
                    ?? fretboard.middleVoicing(of: chords[index], in: position)!
                if pass == 4, index == 1 {
                    drill.handle(.played(Pitch(30), onset: s(onset), at: s(onset)))
                    previous = nil
                    continue
                }
                for (offset, pitch) in voicing.locations.map(fretboard.pitch).enumerated() {
                    let time = onset + Double(offset) * 0.3
                    drill.handle(.played(pitch, onset: s(time), at: s(time)))
                }
                previous = voicing
            }
        }
        drill.handle(.tick(at: s(4 + Double(timesThrough * 16) + 2)))
        return drill.attempts
    }

    @Test func cleanChordsTimesThroughWhenHiddenAndTheHardest() {
        let summary = ChordRunSummary(attempts: run(timesThrough: 6))
        #expect(summary.chords == 24)
        #expect(summary.clean == 23)
        #expect(summary.timesThrough == 6)
        #expect(summary.firstHidden == 5)
        // Only chords that weren't always clean, fewest clean first, at most two.
        #expect(summary.hardest.map(\.text) == ["D (5 of 6)"])
        #expect(summary.text == "23 of 24 chords clean · 6 times through · Hidden from the 5th")
    }

    @Test func nothingHiddenYet() {
        let summary = ChordRunSummary(attempts: run(timesThrough: 1))
        #expect(summary.firstHidden == nil)
        #expect(summary.hardest.isEmpty)
        #expect(summary.text == "4 of 4 chords clean · 1 time through")
    }
}
