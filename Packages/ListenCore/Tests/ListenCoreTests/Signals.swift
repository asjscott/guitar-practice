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

    /// Repeatable random numbers.
    struct Random {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed &* 104_729
            for _ in 0..<8 { _ = next(0...1) }
        }

        mutating func next(_ range: ClosedRange<Double>) -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Double((state ^ (state >> 29)) & 0xFFFF_FFFF) / Double(UInt64(1) << 32)
            return range.lowerBound + unit * (range.upperBound - range.lowerBound)
        }
    }

    /// A picked string, nearer the recorded clips than `pluck`: the pick's noise, harmonics in no fixed phase, a
    /// little sharp of exact multiples, the higher ones dying faster (35 dB/s more at 1.5 kHz, as in the A string's
    /// clip). It is stopped over its last 5 ms.
    static func pick(frequency: Double, peak: Double, decay: Double, duration: Double, random: inout Random) -> [Float] {
        let count = Int(duration * sampleRate), stop = 0.005 * sampleRate
        var samples = [Double](repeating: 0, count: count)
        for harmonic in 1...24 {
            let number = Double(harmonic)
            let pitch = frequency * number * (1 + 0.00004 * number * number).squareRoot()
            guard pitch < 6000 else { break }
            let phase = random.next(0...2 * .pi), amount = peak * 0.4 * pow(number, -1.1) * random.next(0.5...1.2)
            let rate = 1 / decay + 4 * pitch / 1500
            // Until it has died away by 80 dB.
            for index in 0..<min(count, Int(9.2 / rate * sampleRate)) {
                let time = Double(index) / sampleRate
                samples[index] += amount * min(1, time / 0.003) * exp(-time * rate) * sin(2 * .pi * pitch * time + phase)
            }
        }
        for index in 0..<min(count, 960) {
            samples[index] += peak * 0.02 * exp(-Double(index) / sampleRate / 0.003) * random.next(-1...1)
        }
        return samples.enumerated().map { Float($1 * min(1, Double(count - $0) / stop)) }
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

    /// Silence of the given length.
    static func silence(_ duration: Double, sampleRate: Double = sampleRate) -> [Float] {
        [Float](repeating: 0, count: Int(duration * sampleRate))
    }
}
