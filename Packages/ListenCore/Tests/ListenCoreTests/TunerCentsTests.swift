import Foundation
import Testing
import ListenCore

/// Cents and Hz are exact to within half a cent on a steady plucked tone.
@Suite("Tuner reading: cents and Hz")
struct TunerCentsTests {
    static let centsTolerance = 0.5

    struct Case: CustomTestStringConvertible, Sendable {
        let midi: Int
        let cents: Double
        var testDescription: String { "MIDI \(midi) \(cents >= 0 ? "+" : "")\(cents) cents" }
    }

    static let cases: [Case] = [
        Case(midi: 40, cents: 18),    // low E sharp: 83.3 Hz
        Case(midi: 40, cents: -29),
        Case(midi: 45, cents: 29),
        Case(midi: 45, cents: -18),
        Case(midi: 69, cents: 18),
        Case(midi: 69, cents: -29),
        Case(midi: 86, cents: 29),    // fret 22 on string 1
        Case(midi: 86, cents: -18),
        Case(midi: 38, cents: 0),     // Drop D's low D, in tune
    ]

    @Test(arguments: cases)
    func detunedTone(_ c: Case) throws {
        let frequency = Signals.hz(midi: c.midi, cents: c.cents)
        let window = tunerReadings(Signals.pluck(frequency: frequency), from: 0.2, to: 0.5)
        #expect(!window.isEmpty)
        for reading in window {
            let reading = try #require(reading)
            #expect(reading.midiNote == c.midi)
            #expect(abs(reading.cents - c.cents) <= Self.centsTolerance)
            // Half a cent of frequency, relative.
            #expect(abs(reading.frequency - frequency) <= frequency * 0.0003)
        }
    }

    @Test("Other sample rates and block sizes", arguments: [(44_100.0, 4410), (96_000.0, 256), (48_000.0, 4800)])
    func sampleRateAndBlockSize(sampleRate: Double, blockSize: Int) throws {
        let frequency = Signals.hz(midi: 40, cents: -29)
        let tone = Signals.pluck(frequency: frequency, sampleRate: sampleRate)
        let window = tunerReadings(tone, from: 0.2, to: 0.5, sampleRate: sampleRate, blockSize: blockSize)
        #expect(!window.isEmpty)
        for reading in window {
            let reading = try #require(reading)
            #expect(reading.midiNote == 40)
            #expect(abs(reading.cents - -29) <= Self.centsTolerance)
        }
    }

    @Test func lowESharpReads83Hz() throws {
        // The spec's example tuner line: "+18 cents · 83.3 Hz".
        let window = tunerReadings(Signals.pluck(frequency: 83.27), from: 0.2, to: 0.5)
        let reading = try #require(window.last ?? nil)
        #expect(reading.midiNote == 40)
        #expect((reading.cents).rounded() == 18)
        #expect((reading.frequency * 10).rounded() / 10 == 83.3)
    }

    @Test func inTuneWithinFiveCents() throws {
        let inTune = try #require(tunerReadings(Signals.pluck(frequency: Signals.hz(midi: 45, cents: 4)), from: 0.2, to: 0.5).last ?? nil)
        let sharp = try #require(tunerReadings(Signals.pluck(frequency: Signals.hz(midi: 45, cents: 7)), from: 0.2, to: 0.5).last ?? nil)
        let flat = try #require(tunerReadings(Signals.pluck(frequency: Signals.hz(midi: 45, cents: -7)), from: 0.2, to: 0.5).last ?? nil)
        #expect(inTune.isInTune)
        #expect(!sharp.isInTune)
        #expect(!flat.isInTune)
    }
}
