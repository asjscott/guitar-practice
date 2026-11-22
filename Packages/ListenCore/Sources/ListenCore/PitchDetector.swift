import Accelerate
import Foundation

/// McLeod Pitch Method (MPM) detector: one window of samples in, a frequency
/// estimate out. Internal to ListenCore; the listener is the public face (ADR 0002).
///
/// Reference: P. McLeod and G. Wyvill, "A smarter way to find pitch" (2005).
struct PitchDetector: Sendable {
    /// One pitch estimate: frequency and clarity (the NSDF peak height, 0–1).
    struct Estimate: Sendable, Equatable {
        let frequency: Double
        let clarity: Double
    }

    let sampleRate: Double
    /// Lowest and highest frequency the detector looks for.
    let frequencyRange: ClosedRange<Double>
    /// A key maximum counts if it reaches this fraction of the highest one (MPM's k).
    let peakThreshold: Double
    /// Below this clarity the window has no clear pitch.
    let minimumClarity: Double

    init(
        sampleRate: Double,
        frequencyRange: ClosedRange<Double> = 60...1500,
        peakThreshold: Double = 0.93,
        minimumClarity: Double = 0.8
    ) {
        self.sampleRate = sampleRate
        self.frequencyRange = frequencyRange
        self.peakThreshold = peakThreshold
        self.minimumClarity = minimumClarity
    }

    /// The pitch of a window, or nil if it has no clear pitch in range.
    func estimate(_ window: [Float]) -> Estimate? {
        let minLag = max(2, Int(sampleRate / frequencyRange.upperBound))
        let maxLag = min(window.count / 2, Int(sampleRate / frequencyRange.lowerBound) + 1)
        guard maxLag > minLag + 2 else { return nil }
        let nsdf = normalizedSquareDifference(window, maxLag: maxLag)

        // Key maxima: the highest point of each positive region after the first
        // negative region (this skips the lag-zero peak).
        var keyMaxima: [Int] = []
        var lag = 1
        while lag < maxLag, nsdf[lag] > 0 { lag += 1 }
        while lag < maxLag {
            while lag < maxLag, nsdf[lag] <= 0 { lag += 1 }
            var best = -1
            while lag < maxLag, nsdf[lag] > 0 {
                if best < 0 || nsdf[lag] > nsdf[best] { best = lag }
                lag += 1
            }
            if best >= minLag, best < maxLag - 1 { keyMaxima.append(best) }
        }
        guard let highest = keyMaxima.map({ nsdf[$0] }).max() else { return nil }
        guard let chosen = keyMaxima.first(where: { nsdf[$0] >= peakThreshold * highest }) else { return nil }

        // Parabolic interpolation around the chosen peak.
        let a = nsdf[chosen - 1], b = nsdf[chosen], c = nsdf[chosen + 1]
        let denominator = a - 2 * b + c
        let shift = denominator == 0 ? 0 : 0.5 * (a - c) / denominator
        let period = Double(chosen) + shift
        let clarity = b - 0.25 * (a - c) * shift
        guard clarity >= minimumClarity else { return nil }
        let frequency = sampleRate / period
        guard frequencyRange.contains(frequency) else { return nil }
        return Estimate(frequency: frequency, clarity: min(clarity, 1))
    }

    /// NSDF n(τ) = 2·r(τ) / m(τ) for τ in 0..<maxLag.
    private func normalizedSquareDifference(_ window: [Float], maxLag: Int) -> [Double] {
        let n = window.count
        var result = [Double](repeating: 0, count: maxLag)
        window.withUnsafeBufferPointer { x in
            // m(τ) = Σ x[j]² + x[j+τ]² over j in 0..<(n-τ), updated incrementally.
            var energy = 0.0
            for j in 0..<n { energy += 2 * Double(x[j]) * Double(x[j]) }
            for tau in 0..<maxLag {
                if tau > 0 {
                    let head = Double(x[tau - 1]), tail = Double(x[n - tau])
                    energy -= head * head + tail * tail
                }
                // vDSP keeps this fast in Debug builds too, so the app can listen live.
                var r: Float = 0
                vDSP_dotpr(x.baseAddress!, 1, x.baseAddress! + tau, 1, &r, vDSP_Length(n - tau))
                result[tau] = energy > 0 ? 2 * Double(r) / energy : 0
            }
        }
        return result
    }
}
