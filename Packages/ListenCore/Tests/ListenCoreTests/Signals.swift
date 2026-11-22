import Foundation

/// Synthetic test signals. Frequencies come from MIDI notes by the
/// textbook formula (A4 = 440 Hz), independently of ListenCore.
enum Signals {
    static let sampleRate = 48_000.0

    /// Equal-tempered frequency of a MIDI note, plus an optional offset in cents.
    static func hz(midi: Int, cents: Double = 0) -> Double {
        440 * pow(2, (Double(midi - 69) + cents / 100) / 12)
    }

    /// A plucked tone: harmonics 1…n with the given amplitudes, decaying exponentially.
    static func pluck(
        frequency: Double,
        harmonics: [Double] = [1, 0.5, 0.33, 0.25, 0.2],
        peak: Double = 0.5,
        decay: Double = 1.2,
        duration: Double = 0.6,
        sampleRate: Double = sampleRate
    ) -> [Float] {
        let count = Int(duration * sampleRate)
        let total = harmonics.reduce(0, +)
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            var s = 0.0
            for (k, a) in harmonics.enumerated() {
                s += a * sin(2 * .pi * frequency * Double(k + 1) * t)
            }
            return Float(peak * exp(-t / decay) * s / total)
        }
    }

    /// A steady sine.
    static func sine(frequency: Double, amplitude: Double, duration: Double, sampleRate: Double = sampleRate) -> [Float] {
        (0..<Int(duration * sampleRate)).map { i in
            Float(amplitude * sin(2 * .pi * frequency * Double(i) / sampleRate))
        }
    }

    /// Uniform white noise with the given RMS level, from a fixed seed.
    static func noise(rms: Double, duration: Double, seed: UInt64 = 1, sampleRate: Double = sampleRate) -> [Float] {
        var state = seed
        let scale = rms * sqrt(3.0)   // uniform on [-a, a] has RMS a/√3
        return (0..<Int(duration * sampleRate)).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let u = Double(state >> 11) / Double(UInt64(1) << 53)   // 0..<1
            return Float((u * 2 - 1) * scale)
        }
    }

    /// Linear amplitude for a level in dBFS.
    static func amplitude(dBFS: Double) -> Double { pow(10, dBFS / 20) }

    /// Sample-wise sum of two signals (the shorter one padded with silence).
    static func mix(_ a: [Float], _ b: [Float]) -> [Float] {
        (0..<max(a.count, b.count)).map { i in
            (i < a.count ? a[i] : 0) + (i < b.count ? b[i] : 0)
        }
    }
}
