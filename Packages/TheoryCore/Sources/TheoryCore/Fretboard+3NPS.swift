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
        return (1...notes.count).flatMap { number in
            placements(of: walk(notes, from: number - 1, notesPerString: 3))
                .enumerated().map { octave, locations in
                    Position(id: .init(system: .threeNotesPerString, number: number, octave: octave),
                             scale: scale,
                             name: Position.ID(system: .threeNotesPerString, number: number).name(in: tuning),
                             locations: locations)
                }
        }
        .sortedUpTheNeck()
    }

    /// The positions of a scale in a position system. 3NPS gives 3NPS patterns for seven-note
    /// scales; pentatonic and blues have none, so they always get the CAGED shapes.
    public func positions(of scale: Scale, system: Position.System) -> [Position] {
        switch system {
        case .threeNotesPerString where scale.kind.isSevenNote: threeNPSPositions(of: scale)
        case .caged, .threeNotesPerString: cagedPositions(of: scale)
        }
    }
}
