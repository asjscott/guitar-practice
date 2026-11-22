import Foundation

/// Tuner smoothing: the median of the last few estimates, in log frequency.
/// A jump of more than half a semitone starts afresh, so a new note shows at once.
struct PitchSmoother: Sendable {
    private var recent: [Double] = []   // log2 of frequency
    private let capacity = 5
    private let jump = 0.5 / 12          // half a semitone, in octaves

    /// Adds an estimate in Hz; returns the smoothed frequency in Hz.
    mutating func add(_ frequency: Double) -> Double {
        let value = log2(frequency)
        if let current = median, abs(value - current) > jump { recent.removeAll() }
        recent.append(value)
        if recent.count > capacity { recent.removeFirst() }
        return pow(2, median!)
    }

    private var median: Double? {
        guard !recent.isEmpty else { return nil }
        let sorted = recent.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
