import Foundation

extension Fretboard {
    /// The playable locations on one string within a fret range, by fret. Frets below the
    /// capo and past the last fret are left out.
    public func locations(onString string: Int, frets: ClosedRange<Int>) -> [FretboardLocation] {
        guard strings.contains(string), frets.overlaps(playableFrets) else { return [] }
        return frets.clamped(to: playableFrets).map { FretboardLocation(string: string, fret: $0) }
    }

    /// The playable locations of a pitch class on one string within a fret range, by fret.
    public func locations(of pitchClass: PitchClass, onString string: Int, frets: ClosedRange<Int>) -> [FretboardLocation] {
        locations(onString: string, frets: frets).filter { pitch(at: $0).pitchClass == pitchClass }
    }

    /// The playable location of an exact pitch on one string within a fret range, if any.
    /// A pitch occurs at most once on a string.
    public func location(of pitch: Pitch, onString string: Int, frets: ClosedRange<Int>) -> FretboardLocation? {
        locations(onString: string, frets: frets).first { self.pitch(at: $0) == pitch }
    }
}
