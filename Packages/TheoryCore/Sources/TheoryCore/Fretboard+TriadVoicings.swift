import Foundation

/// One playable way to fret a triad (see "Triad voicing" in GLOSSARY.md): a chord, an inversion
/// and a string set at one place on the neck, one note per string.
public struct TriadVoicing: Hashable, Sendable {
    public let triad: Triad
    public let inversion: Triad.Inversion
    public let stringSet: StringSet

    /// One location per string of the set, lowest string first.
    public let locations: [FretboardLocation]

    /// The frets the voicing covers, lowest to highest (open strings count as fret 0).
    public var frets: ClosedRange<Int> { locations.fretSpan }

    /// The order up the neck.
    func isBelow(_ other: TriadVoicing) -> Bool {
        (frets.lowerBound, locations[0].fret) < (other.frets.lowerBound, other.locations[0].fret)
    }
}

extension Fretboard {
    /// The most frets a triad voicing may cover, counting both ends (5–8 is 4 frets).
    public static let maxTriadVoicingSpan = 4

    /// A voicing's locations in the order its notes are played, low to high by pitch, whatever order its strings are
    /// in (a re-entrant tuning may have a higher string sounding lower).
    public func locationsLowToHigh(of voicing: TriadVoicing) -> [FretboardLocation] {
        voicing.locations.sorted { pitch(at: $0) < pitch(at: $1) }
    }

    /// A voicing's pitches, low to high.
    public func pitches(of voicing: TriadVoicing) -> [Pitch] { locationsLowToHigh(of: voicing).map(pitch) }

    /// A voicing's highest pitch: its top note.
    public func topPitch(of voicing: TriadVoicing) -> Pitch {
        let pitches = pitches(of: voicing)
        return pitches[pitches.count - 1]
    }

    /// The string sets this tuning has strings for, lowest first: all four on six or more
    /// strings (sets are counted from string 6 up), fewer on a shorter neck.
    public var stringSets: [StringSet] {
        StringSet.allCases.filter { strings.contains($0.strings.upperBound) }
    }

    /// Every voicing of a triad in an inversion on a string set, ordered up the neck.
    ///
    /// Voicings are in close position: the inversion's tones (for example 3 5 R) go up the set's
    /// strings in that order, each higher in pitch than the one below, all within an octave of
    /// the lowest note. So every voicing is the inversion's three tones stacked as tightly as
    /// they go; spread (open) voicings such as R 5 3, or a top note more than an octave above
    /// the bass, are never produced. Every location is playable (capo–22) and the voicing covers
    /// at most `maxTriadVoicingSpan` frets.
    public func voicings(of triad: Triad, inversion: Triad.Inversion, on stringSet: StringSet) -> [TriadVoicing] {
        precondition(stringSets.contains(stringSet), "String set \(stringSet) is not on this tuning")
        let tones = triad.tones(in: inversion).map(\.pitchClass)
        let candidates = zip(stringSet.strings, tones).map { string, tone in
            playableFrets.map { FretboardLocation(string: string, fret: $0) }
                .filter { pitch(at: $0).pitchClass == tone }
        }

        var voicings: [TriadVoicing] = []
        for bass in candidates[0] {
            let bassPitch = pitch(at: bass)
            for middle in candidates[1] where pitch(at: middle) > bassPitch {
                for top in candidates[2] where pitch(at: top) > pitch(at: middle)
                    && (pitch(at: top) - bassPitch).semitones < 12 {
                    let voicing = TriadVoicing(triad: triad, inversion: inversion, stringSet: stringSet,
                                               locations: [bass, middle, top])
                    if voicing.frets.count <= Fretboard.maxTriadVoicingSpan {
                        voicings.append(voicing)
                    }
                }
            }
        }
        return voicings.sorted { $0.isBelow($1) }
    }

    /// How many of a key's chords have a voicing on a string set, anywhere on the neck.
    public func chordCount(of key: Key, on stringSet: StringSet) -> Int {
        key.chords.filter { chord in
            Triad.Inversion.allCases.contains { !voicings(of: chord, inversion: $0, on: stringSet).isEmpty }
        }.count
    }

    /// The voicings wholly within a fret range, ordered up the neck.
    public func voicings(of triad: Triad, inversion: Triad.Inversion, on stringSet: StringSet,
                         frets: ClosedRange<Int>) -> [TriadVoicing] {
        voicings(of: triad, inversion: inversion, on: stringSet).filter { $0.locations.allSatisfy { frets.contains($0.fret) } }
    }

    /// The voicings in every inversion wholly within a fret range, ordered up the neck.
    public func voicings(of triad: Triad, on stringSet: StringSet, frets: ClosedRange<Int>) -> [TriadVoicing] {
        Triad.Inversion.allCases.flatMap { voicings(of: triad, inversion: $0, on: stringSet, frets: frets) }
            .sorted { $0.isBelow($1) }
    }
}
