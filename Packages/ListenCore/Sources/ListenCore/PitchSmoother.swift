import Foundation

/// Tuner smoothing, in log frequency: the median of the last few estimates
/// (drops outliers), then an exponential average (steadies the needle).
/// A jump of more than half a semitone starts afresh, so a new note shows at once.
struct PitchSmoother: Sendable {
    private var recent: [Double] = []   // log2 of frequency
    private var average: Double?
    private let capacity = 5
    /// Weight of each new median in the average; about 60 ms to settle at 48 kHz.
    private let weight = 0.15
    private let jump = 0.5 / 12          // half a semitone, in octaves

    /// Adds an estimate in Hz; returns the smoothed frequency in Hz.
    mutating func add(_ frequency: Double) -> Double {
        let value = log2(frequency)
        if let current = average, abs(value - current) > jump {
            recent.removeAll()
            average = nil
        }
        recent.append(value)
        if recent.count > capacity { recent.removeFirst() }
        let median = Self.median(of: recent)
        let smoothed = average.map { $0 + weight * (median - $0) } ?? median
        average = smoothed
        return pow(2, smoothed)
    }

    private static func median(of values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
