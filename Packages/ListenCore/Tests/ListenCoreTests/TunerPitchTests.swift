import Testing
import ListenCore

@Suite("Tuner reading: nearest pitch")
struct TunerPitchTests {
    /// Every reading 0.1–0.5 s into the signal names the expected MIDI note.
    func expectPitch(of samples: [Float], is midi: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        let window = tunerReadings(samples, from: 0.1, to: 0.5)
        #expect(!window.isEmpty, sourceLocation: sourceLocation)
        for reading in window {
            #expect(reading?.midiNote == midi, sourceLocation: sourceLocation)
        }
    }

    @Test("Open strings in standard tuning", arguments: [40, 45, 50, 55, 59, 64])
    func openStringsInStandardTuning(midi: Int) {
        expectPitch(of: Signals.pluck(frequency: Signals.hz(midi: midi)), is: midi)
    }

    @Test func dropDLowD() {
        // D2, 73.4 Hz: the lowest note the app must hear.
        expectPitch(of: Signals.pluck(frequency: 73.416), is: 38)
    }

    @Test("No octave error when the 2nd harmonic is stronger", arguments: [38, 40, 45, 50, 64])
    func strongSecondHarmonic(midi: Int) {
        // The 2nd harmonic is twice the fundamental, as on a low string picked near the bridge.
        let tone = Signals.pluck(frequency: Signals.hz(midi: midi), harmonics: [0.5, 1, 0.4, 0.3, 0.2])
        expectPitch(of: tone, is: midi)
    }

    @Test func fret22OnString1() {
        // E4 + 22 frets = D6, 1174.7 Hz: the top of the neck.
        expectPitch(of: Signals.pluck(frequency: 1174.66), is: 86)
    }
}
