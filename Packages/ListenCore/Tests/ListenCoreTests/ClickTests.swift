import Foundation
import Testing
import ListenCore

/// The metronome click's samples: short, and stronger when emphasised.
@Suite("Click")
struct ClickTests {
    /// RMS level in dBFS.
    static func level(_ samples: some Collection<Float>) -> Double {
        20 * log10(sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)))
    }

    /// The frequency that half the energy lies below.
    static func medianFrequency(_ samples: [Float], sampleRate: Double) -> Double {
        let powers = stride(from: 50.0, to: 15_000, by: 50).map { frequency in
            var real = 0.0, imaginary = 0.0
            for (index, sample) in samples.enumerated() {
                let angle = 2 * .pi * frequency * Double(index) / sampleRate
                real += Double(sample) * cos(angle)
                imaginary += Double(sample) * sin(angle)
            }
            return (frequency: frequency, power: real * real + imaginary * imaginary)
        }
        let half = powers.reduce(0) { $0 + $1.power } / 2
        var sum = 0.0
        for entry in powers {
            sum += entry.power
            if sum >= half { return entry.frequency }
        }
        return 0
    }

    @Test("Quiet within 40 ms", arguments: [44_100.0, 48_000, 96_000], [false, true])
    func quietWithin40ms(sampleRate: Double, emphasised: Bool) {
        let click = Click.samples(emphasised: emphasised, sampleRate: sampleRate)
        #expect(Double(click.count) / sampleRate <= 0.04)
        // Even played at full scale, the last 5 ms are below the listener's gate.
        let peak = click.map(abs).max() ?? 0
        let tail = click.suffix(Int(0.005 * sampleRate)).map { $0 / peak }
        #expect(Self.level(tail) < -50)
    }

    @Test("Struck: loudest at the start", arguments: [false, true])
    func struck(emphasised: Bool) {
        let click = Click.samples(emphasised: emphasised, sampleRate: 48_000)
        let peak = click.map(abs).max() ?? 0
        #expect(peak > 0.1 && peak <= 1)
        #expect(click.prefix(240).map(abs).max() == peak)      // 5 ms
    }

    @Test func theEmphasisedClickIsHigherAndLouder() {
        let normal = Click.samples(emphasised: false, sampleRate: 48_000)
        let emphasised = Click.samples(emphasised: true, sampleRate: 48_000)
        #expect(Self.level(emphasised) > Self.level(normal) + 3)
        let (low, high) = (Self.medianFrequency(normal, sampleRate: 48_000), Self.medianFrequency(emphasised, sampleRate: 48_000))
        #expect(high > 1.19 * low)      // at least a minor third
    }
}
