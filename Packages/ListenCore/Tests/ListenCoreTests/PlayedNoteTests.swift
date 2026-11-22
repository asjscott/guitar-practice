import Testing
import ListenCore

/// A pitch held stable for about 80 ms, within ±30 cents, is a played note,
/// stamped with its onset. One pluck gives at most one.
@Suite("Played notes")
struct PlayedNoteTests {
    /// How close the onset must be to the synthetic pluck time, in seconds.
    static let onsetTolerance = 0.005

    @Test("A stable tone gives one played note", arguments: [40, 45, 50, 55, 59, 64, 38, 86])
    func stableTone(midi: Int) throws {
        // Pluck after 0.25 s of silence, in a stream that started at 10 s.
        let tone = Signals.silence(0.25) + Signals.pluck(frequency: Signals.hz(midi: midi), duration: 0.8)
        let notes = playedNotes(tone, startTime: 10)
        try #require(notes.count == 1)
        #expect(notes[0].midiNote == midi)
        #expect(abs(notes[0].cents) <= 0.5)
        #expect(abs(notes[0].onset - 10.25) <= Self.onsetTolerance)
    }
}
