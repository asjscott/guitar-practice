import Testing
import ListenCore

/// Readings are steady enough to tune by, yet follow a new note at once.
@Suite("Tuner reading: smoothing")
struct TunerSmoothingTests {
    @Test func noisyToneReadsSteadily() throws {
        // An in-tune low E with noise only 12 dB below it. Once settled, every
        // reading stays inside half the ±5 cents in-tune band.
        let tone = Signals.mix(
            Signals.pluck(frequency: Signals.hz(midi: 40), decay: 100, duration: 1),
            Signals.noise(rms: Signals.amplitude(dBFS: -26), duration: 1)
        )
        let window = tunerReadings(tone, from: 0.3, to: 1)
        #expect(!window.isEmpty)
        for reading in window {
            let reading = try #require(reading)
            #expect(reading.midiNote == 40)
            #expect(abs(reading.cents) <= TunerReading.inTuneCents / 2)
        }
    }

    @Test func newNoteShowsWithinSixtyMilliseconds() throws {
        // A2 for half a second, then straight to E3 with no gap.
        let tone = Signals.pluck(frequency: Signals.hz(midi: 45), decay: 100, duration: 0.5)
            + Signals.pluck(frequency: Signals.hz(midi: 52), decay: 100, duration: 0.5)
        var listener = Listener()
        let outputs = feed(tone, to: &listener)
        let first = try #require(outputs.first { $0.time > 0.5 && $0.output.tunerReading?.midiNote == 52 })
        #expect(first.time - 0.5 <= 0.06)
        #expect(outputs.filter { $0.time > 0.6 }.allSatisfy { $0.output.tunerReading?.midiNote == 52 })
    }
}
