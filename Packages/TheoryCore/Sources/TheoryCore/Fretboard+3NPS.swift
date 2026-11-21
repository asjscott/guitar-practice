import Foundation

/// 3NPS pattern generation for any tuning (ADR-0001), and the positions for a position system.
extension Fretboard {
    /// The 3NPS patterns of a seven-note scale, placed between the capo and the last fret,
    /// ordered up the neck (by lowest fret, then pattern number). Each pattern appears at its
    /// lowest fit and, when it fits, an octave higher. Empty for pentatonic and blues scales.
    ///
    /// Pattern n starts on scale degree n on string 6, and every string takes the next three
    /// scale notes going up. Each string's first note sits nearest the previous string's first
    /// note (the plain pitch walk in rising tunings; stays compact in re-entrant ones), as for
    /// CAGED shapes. Patterns are named "Pattern 1"–"Pattern 7", numbered from the scale's own
    /// tonic (so a minor scale's pattern 1 starts on the minor tonic).
    public func threeNPSPositions(of scale: Scale) -> [Position] {
        guard scale.kind.isSevenNote else { return [] }
        let notes = scale.pitchClasses
        let positions = (1...notes.count).flatMap { number in
            placements(ofShape: threeNotesPerStringWalk(notes, from: number - 1))
                .enumerated().map { octave, locations in
                    Position(id: .init(system: .threeNotesPerString, number: number, octave: octave),
                             scale: scale,
                             name: "Pattern \(number)",
                             locations: locations)
                }
        }
        return positions.sorted { ($0.frets.lowerBound, $0.number) < ($1.frets.lowerBound, $1.number) }
    }

    /// The positions of a scale in a position system. 3NPS gives 3NPS patterns for seven-note
    /// scales; pentatonic and blues have none, so they always get the CAGED shapes.
    public func positions(of scale: Scale, system: Position.System) -> [Position] {
        switch system {
        case .threeNotesPerString where scale.kind.isSevenNote: threeNPSPositions(of: scale)
        case .caged, .threeNotesPerString: cagedPositions(of: scale)
        }
    }

    /// Three scale notes per string from string 6 up, starting on `notes[start]`, in relative frets.
    private func threeNotesPerStringWalk(_ notes: [PitchClass], from start: Int) -> [FretboardLocation] {
        var locations: [FretboardLocation] = []
        var anchor: Int?
        for string in strings {
            let index = start + 3 * (string - strings.lowerBound)
            let first = relativeFret(of: notes[index % notes.count], onString: string, near: anchor)
            var fret = first
            locations.append(FretboardLocation(string: string, fret: fret))
            for step in 1...2 {
                let previous = notes[(index + step - 1) % notes.count]
                fret += previous.interval(upTo: notes[(index + step) % notes.count]).semitones
                locations.append(FretboardLocation(string: string, fret: fret))
            }
            anchor = first
        }
        return locations
    }
}
