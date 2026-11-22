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

    @Test("Within ±30 cents is a played note", arguments: [(40, 29.0), (40, -29.0), (64, 29.0), (64, -29.0), (86, 29.0)])
    func within30Cents(midi: Int, cents: Double) throws {
        let notes = playedNotes(Signals.pluck(frequency: Signals.hz(midi: midi, cents: cents)))
        try #require(notes.count == 1)
        #expect(notes[0].midiNote == midi)
        #expect(abs(notes[0].cents - cents) <= 0.5)
    }

    @Test("Beyond ±30 cents is no played note", arguments: [(40, 31.0), (40, -31.0), (64, 31.0), (64, -31.0), (86, -31.0)])
    func beyond30Cents(midi: Int, cents: Double) {
        #expect(playedNotes(Signals.pluck(frequency: Signals.hz(midi: midi, cents: cents))).isEmpty)
    }

    @Test("A tone shorter than the stability window is no played note", arguments: [40, 45, 64, 86])
    func shortTone(midi: Int) {
        // 60 ms of steady tone, then silence.
        let tone = Signals.silence(0.1)
            + Signals.pluck(frequency: Signals.hz(midi: midi), decay: 100, duration: 0.06)
            + Signals.silence(0.5)
        #expect(playedNotes(tone).isEmpty)
    }

    @Test("A decaying tail gives no extra played notes", arguments: [40, 52, 64])
    func decayingTail(midi: Int) throws {
        // Rings for 3 s, falling through the gate at about 2 s.
        let notes = playedNotes(Signals.pluck(frequency: Signals.hz(midi: midi), decay: 0.5, duration: 3))
        try #require(notes.count == 1)
        #expect(notes[0].midiNote == midi)
    }

    @Test("Plucking the same note again gives a second played note", arguments: [40, 45, 64])
    func samePitchTwice(midi: Int) throws {
        // The second pluck comes while the first still rings at 60 % of its peak.
        let pluck = Signals.pluck(frequency: Signals.hz(midi: midi), duration: 0.6)
        let notes = playedNotes(pluck + pluck)
        try #require(notes.count == 2)
        #expect(notes.allSatisfy { $0.midiNote == midi })
        #expect(abs(notes[0].onset - 0) <= Self.onsetTolerance)
        #expect(abs(notes[1].onset - 0.6) <= Self.onsetTolerance)
    }

    @Test func aNewNoteAfterSilenceIsANewPlayedNote() throws {
        let pluck = Signals.pluck(frequency: Signals.hz(midi: 45), duration: 0.4)
        let notes = playedNotes(pluck + Signals.silence(0.2) + pluck)
        try #require(notes.count == 2)
        #expect(abs(notes[1].onset - 0.6) <= Self.onsetTolerance)
    }

    @Test func aDifferentNotePluckedOverTheLastIsANewPlayedNote() throws {
        // Straight from a ringing A2 to E3. The tuner's smoothing lags a jump like
        // this; played notes come from unsmoothed estimates, so they don't.
        let reported = reportedNotes(
            Signals.pluck(frequency: Signals.hz(midi: 45), duration: 0.5)
                + Signals.pluck(frequency: Signals.hz(midi: 52), duration: 0.5)
        )
        try #require(reported.count == 2)
        #expect(reported.map(\.note.midiNote) == [45, 52])
        #expect(abs(reported[1].note.cents) <= 0.5)
        #expect(abs(reported[1].note.onset - 0.5) <= Self.onsetTolerance)
        #expect(reported[1].reportedAt - 0.5 <= 0.15)
    }

    @Test func noiseAndHumBelowTheGateAreNoPlayedNotes() {
        let hum = (1...4).map { k in
            Signals.sine(frequency: 50 * Double(k), amplitude: Signals.amplitude(dBFS: -58), duration: 2)
        }.reduce([Float](), Signals.mix)
        #expect(playedNotes(Signals.noise(rms: Signals.amplitude(dBFS: -56), duration: 2)).isEmpty)
        #expect(playedNotes(hum).isEmpty)
        // An open A at about −56 dBFS RMS: a clear pitch, but under the gate.
        #expect(playedNotes(Signals.pluck(frequency: Signals.hz(midi: 45), peak: 0.0042, decay: 100, duration: 2)).isEmpty)
    }

    @Test("Low E is reported within 150 ms of its onset", arguments: [256, 512, 1024])
    func lowELatency(blockSize: Int) throws {
        // Measured in sample time, at the end of the block that reports the note.
        let reported = reportedNotes(
            Signals.silence(0.3) + Signals.pluck(frequency: Signals.hz(midi: 40), duration: 0.6),
            blockSize: blockSize
        )
        let first = try #require(reported.first)
        #expect(first.note.midiNote == 40)
        #expect(first.reportedAt - 0.3 <= 0.15)
    }

    @Test("Other sample rates and block sizes", arguments: [(44_100.0, 4410), (96_000.0, 256), (48_000.0, 4800)])
    func sampleRateAndBlockSize(sampleRate: Double, blockSize: Int) throws {
        let tone = Signals.silence(0.25, sampleRate: sampleRate)
            + Signals.pluck(frequency: Signals.hz(midi: 40), sampleRate: sampleRate)
        let notes = playedNotes(tone, sampleRate: sampleRate, blockSize: blockSize)
        try #require(notes.count == 1)
        #expect(notes[0].midiNote == 40)
        #expect(abs(notes[0].onset - 0.25) <= Self.onsetTolerance)
    }
}
