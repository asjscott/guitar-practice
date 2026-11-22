import Testing
import ListenCore

/// Below the gate (about −50 dBFS) the listener reports no signal.
@Suite("Noise gate")
struct NoiseGateTests {
    func expectNoSignal(_ samples: [Float], sourceLocation: SourceLocation = #_sourceLocation) {
        let window = tunerReadings(samples, from: 0, to: 2)
        #expect(!window.isEmpty, sourceLocation: sourceLocation)
        #expect(window.allSatisfy { $0 == nil }, sourceLocation: sourceLocation)
    }

    @Test func silence() {
        expectNoSignal([Float](repeating: 0, count: 48_000))
    }

    @Test func whiteNoiseBelowTheGate() {
        expectNoSignal(Signals.noise(rms: Signals.amplitude(dBFS: -56), duration: 1))
    }

    @Test("Mains buzz below the gate", arguments: [50.0, 60.0])
    func buzzBelowTheGate(mains: Double) {
        // Mains hum and its harmonics, about −56 dBFS RMS in all: pitched, but too quiet to count.
        let buzz = (1...4).map { k in
            Signals.sine(frequency: mains * Double(k), amplitude: Signals.amplitude(dBFS: -58), duration: 1)
        }.reduce([Float](), Signals.mix)
        expectNoSignal(buzz)
    }

    @Test func quietStringBelowTheGate() {
        // An open A at about −56 dBFS RMS: a clear pitch, but under the gate.
        expectNoSignal(Signals.pluck(frequency: Signals.hz(midi: 45), peak: 0.0042, decay: 100, duration: 1))
    }

    @Test func quietStringAboveTheGateIsHeard() throws {
        // The same string at about −44 dBFS RMS is heard.
        let tone = Signals.pluck(frequency: Signals.hz(midi: 45), peak: 0.017, decay: 100, duration: 1)
        let reading = try #require(tunerReadings(tone, from: 0.3, to: 0.6).last ?? nil)
        #expect(reading.midiNote == 45)
    }

    @Test func pitchedToneOverNoiseIsHeard() throws {
        let tone = Signals.mix(
            Signals.pluck(frequency: Signals.hz(midi: 45), duration: 1),
            Signals.noise(rms: Signals.amplitude(dBFS: -56), duration: 1)
        )
        let reading = try #require(tunerReadings(tone, from: 0.3, to: 0.6).last ?? nil)
        #expect(reading.midiNote == 45)
    }

    @Test func decayingPluckGoesToNoSignalAtTheGate() {
        // Default harmonics at peak 0.5 start near −14.5 dBFS RMS. With a 0.25 s
        // decay the level falls 34.7 dB/s, so it crosses −50 dBFS at about 1.02 s.
        let tone = Signals.pluck(frequency: Signals.hz(midi: 52), decay: 0.25, duration: 2)
        var listener = Listener()
        let outputs = feed(tone, to: &listener)
        let before = outputs.filter { $0.time > 0.1 && $0.time < 0.85 }
        let after = outputs.filter { $0.time > 1.2 }
        #expect(!before.isEmpty && !after.isEmpty)
        #expect(before.allSatisfy { $0.output.tunerReading?.midiNote == 52 })
        #expect(after.allSatisfy { $0.output.tunerReading == nil })
    }

    @Test func loudNoiseWithNoPitchIsNoReading() {
        // Above the gate but unpitched: there is nothing to tune to.
        expectNoSignal(Signals.noise(rms: Signals.amplitude(dBFS: -20), duration: 1))
    }
}
