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

extension Tuning {
    /// For a standard-interval tuning with its low string dropped a whole tone (Drop D), the
    /// same tuning with string 6 back a fourth below string 5 (Drop D → standard). Nil for
    /// every other tuning.
    var undroppingLowString: Tuning? {
        guard hasStandardIntervals, (openPitches[1] - openPitches[0]).semitones != 5 else { return nil }
        return Tuning([openPitches[1] - Interval(5)] + openPitches.dropFirst())
    }
}
