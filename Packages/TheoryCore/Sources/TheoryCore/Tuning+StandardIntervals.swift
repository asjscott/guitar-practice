import Foundation

extension Tuning {
    /// True when the strings are a fourth apart except a major third from string 3 to string 2,
    /// as in standard tuning, at any pitch (E♭ standard). The low string may also be dropped a
    /// whole tone (Drop D). Only these tunings use the C A G E D names (ADR-0001).
    public var hasStandardIntervals: Bool {
        guard stringCount == 6 else { return false }
        let intervals = zip(openPitches.dropFirst(), openPitches).map { ($0 - $1).semitones }
        return [5, 7].contains(intervals[0]) && Array(intervals.dropFirst()) == [5, 5, 4, 5]
    }
}
