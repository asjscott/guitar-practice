import Foundation

extension Tuning {
    /// The open pitches a string may be tuned to: MIDI 24 (C1) to 72 (C5).
    public static let openPitchRange: ClosedRange<Pitch> = Pitch(24)...Pitch(72)

    /// True when every open string lies within `openPitchRange`.
    public var isWithinOpenPitchRange: Bool {
        openPitches.allSatisfy(Tuning.openPitchRange.contains)
    }

    /// True when the string can move by the interval and stay within `openPitchRange`.
    public func canRetune(string: Int, by interval: Interval) -> Bool {
        Tuning.openPitchRange.contains(openPitch(ofString: string) + interval)
    }

    /// This tuning with one string moved by the interval, clamped to `openPitchRange`.
    /// Other strings are untouched; the result may be re-entrant.
    public func retuning(string: Int, by interval: Interval) -> Tuning {
        let range = Tuning.openPitchRange
        let moved = openPitch(ofString: string) + interval
        var pitches = openPitches
        pitches[string] = min(max(moved, range.lowerBound), range.upperBound)
        return Tuning(pitches)
    }
}
