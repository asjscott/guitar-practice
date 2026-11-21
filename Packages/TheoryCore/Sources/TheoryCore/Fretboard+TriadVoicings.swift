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
}

extension Fretboard {
    /// The most frets a triad voicing may cover, counting both ends (5–8 is 4 frets).
    public static let maxTriadVoicingSpan = 4

    /// The string sets this tuning has: every run of three adjacent strings, lowest first.
    public var stringSets: [StringSet] {
        guard strings.count >= 3 else { return [] }
        return (0...(strings.count - 3)).map(StringSet.init(lowestString:))
    }

    /// Every voicing of a triad in an inversion on a string set, ordered up the neck.
    ///
    /// Voicings are in close position: the inversion's tones (for example 3 5 R) go up the set's
    /// strings in that order, each higher in pitch than the one below, all within an octave of
    /// the lowest note. Every location is playable (capo–22) and the voicing covers at most
    /// `maxTriadVoicingSpan` frets.
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
        return voicings.sorted {
            ($0.frets.lowerBound, $0.locations[0].fret) < ($1.frets.lowerBound, $1.locations[0].fret)
        }
    }
}
