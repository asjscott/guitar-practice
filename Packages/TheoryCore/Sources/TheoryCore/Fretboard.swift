import Foundation

/// One string at one fret: the spot a finger presses. Not a "position" (see GLOSSARY.md).
///
/// `string` is the internal index (0 = physical string 6); `fret` counts from the nut (0 = open).
public struct FretboardLocation: Hashable, Sendable, Codable {
    public let string: Int
    public let fret: Int

    public init(string: Int, fret: Int) {
        self.string = string
        self.fret = fret
    }
}

extension FretboardLocation: CustomStringConvertible {
    public var description: String { "(string \(string), fret \(fret))" }
}

/// The neck for a tuning: the one entry point for "where is this note / what is at this spot?"
///
/// Every query is limited to the playable frets, so callers never do fret maths themselves.
/// Results are ordered by string (string 6 first), then by fret.
public struct Fretboard: Hashable, Sendable {
    /// Frets counted from the nut, open string (0) to the last fret.
    public static let frets: ClosedRange<Int> = 0...22

    /// Capo frets: none (0) up to fret 12.
    public static let capoFrets: ClosedRange<Int> = 0...12

    public let tuning: Tuning

    /// The fret the capo sits at (0 = no capo). Fret numbers still count from the nut.
    public let capo: Int

    public init(tuning: Tuning, capo: Int = 0) {
        precondition(Fretboard.capoFrets.contains(capo), "Capo must be at fret 0–12")
        self.tuning = tuning
        self.capo = capo
    }

    /// String indices, 0 = physical string 6.
    public var strings: Range<Int> { tuning.strings }

    /// The frets that can be played: from the capo (or the nut) to the last fret.
    public var playableFrets: ClosedRange<Int> { capo...Fretboard.frets.upperBound }

    /// The frets from the capo (or the nut) to `count` above it, as far as the last fret.
    public func playableFrets(upTo count: Int) -> ClosedRange<Int> {
        capo...max(capo, min(capo + count, Fretboard.frets.upperBound))
    }

    /// What a string sounds when played without fretting: its open pitch raised by the capo.
    public func soundingOpenPitch(ofString string: Int) -> Pitch {
        tuning.openPitch(ofString: string) + Interval(capo)
    }

    /// True when the location is on one of this tuning's strings at a playable fret.
    public func isPlayable(_ location: FretboardLocation) -> Bool {
        strings.contains(location.string) && playableFrets.contains(location.fret)
    }

    /// Every playable location, string 6 first, then by fret.
    public var allLocations: [FretboardLocation] {
        strings.flatMap { string in
            playableFrets.map { FretboardLocation(string: string, fret: $0) }
        }
    }

    /// The pitch sounding at a location (open string pitch plus the fret).
    public func pitch(at location: FretboardLocation) -> Pitch {
        tuning.openPitch(ofString: location.string) + Interval(location.fret)
    }

    /// Every playable location of a pitch class, string 6 first, then by fret.
    public func locations(of pitchClass: PitchClass) -> [FretboardLocation] {
        allLocations.filter { pitch(at: $0).pitchClass == pitchClass }
    }

    /// Every playable location of an exact pitch, string 6 first.
    public func locations(of pitch: Pitch) -> [FretboardLocation] {
        allLocations.filter { self.pitch(at: $0) == pitch }
    }
}
