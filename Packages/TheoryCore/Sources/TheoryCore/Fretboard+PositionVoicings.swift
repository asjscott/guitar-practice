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

    /// The melody on a progression's top notes in the position, one per chord: the first chord's root, as high as a
    /// voicing in the position has it on top (or, if none does, the highest top note one has); then for each next
    /// chord, of the top notes its voicings in the position have, the nearest the one before, the lower when two are
    /// as near. Nil when a chord has no voicing in the position.
    public func topNoteLine(of progression: Progression, in key: Key, position: Position) -> [Pitch]? {
        let chords = progression.chords(in: key)
        var tops: [[Pitch]] = []
        for chord in chords {
            let available = voicings(of: chord, in: position).map { pitch(at: $0.locations[2]) }
            guard !available.isEmpty else { return nil }
            tops.append(available)
        }
        guard let first = tops.first else { return [] }
        var line = [first.filter { $0.pitchClass == chords[0].root.pitchClass }.max() ?? first.max()!]
        for available in tops.dropFirst() {
            let previous = line[line.count - 1]
            line.append(available.min { a, b in
                let (da, db) = (abs((a - previous).semitones), abs((b - previous).semitones))
                return da != db ? da < db : a < b
            }!)
        }
        return line
    }
}
