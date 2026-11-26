import Foundation

extension Fretboard {
    /// A triad's voicings in the position (see "Voicing in the position" in GLOSSARY.md): those whose three locations
    /// all belong to it, in any inversion and on any string set, ordered up the neck.
    public func voicings(of triad: Triad, in position: Position) -> [TriadVoicing] {
        let inPosition = Set(position.locations)
        return stringSets.flatMap { set in
            Triad.Inversion.allCases.flatMap { voicings(of: triad, inversion: $0, on: set) }
        }
        .filter { $0.locations.allSatisfy(inPosition.contains) }
        .sorted { $0.isBelow($1) }
    }

    /// Whether every chord of a progression, played in a key, has a voicing in the position.
    public func fits(_ progression: Progression, in key: Key, position: Position) -> Bool {
        Set(progression.chords(in: key)).allSatisfy { !voicings(of: $0, in: position).isEmpty }
    }

    /// How far the hand moves from one voicing to another: the semitones each voice moves, lowest to lowest, middle to
    /// middle and top to top, added up.
    public func movement(from a: TriadVoicing, to b: TriadVoicing) -> Int {
        zip(a.locations, b.locations).map { abs((pitch(at: $1) - pitch(at: $0)).semitones) }.reduce(0, +)
    }

    /// A triad's voicings in the position with the least movement from another voicing, ordered up the neck; all of
    /// them when tied. Empty when the triad has none in the position.
    public func nearestVoicings(of triad: Triad, in position: Position, to voicing: TriadVoicing) -> [TriadVoicing] {
        let candidates = voicings(of: triad, in: position)
        guard let least = candidates.map({ movement(from: voicing, to: $0) }).min() else { return [] }
        return candidates.filter { movement(from: voicing, to: $0) == least }
    }

    /// The triad's voicing in the position nearest its middle: the one whose locations, on average, are closest to
    /// the centre of the position's strings and frets, counting a string and a fret alike. A tie goes to the lower one
    /// on the neck; nil when it has none.
    public func middleVoicing(of triad: Triad, in position: Position) -> TriadVoicing? {
        let strings = position.locations.map(\.string)
        let centre = (string: Double(strings.min()! + strings.max()!) / 2,
                      fret: Double(position.frets.lowerBound + position.frets.upperBound) / 2)
        func distance(_ voicing: TriadVoicing) -> Double {
            let count = Double(voicing.locations.count)
            let string = Double(voicing.locations.map(\.string).reduce(0, +)) / count - centre.string
            let fret = Double(voicing.locations.map(\.fret).reduce(0, +)) / count - centre.fret
            return string * string + fret * fret
        }
        return voicings(of: triad, in: position).min { distance($0) < distance($1) }
    }
}
