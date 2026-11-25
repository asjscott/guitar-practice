import Foundation

/// Placement shared by every position system (ADR-0001): a position's locations are generated
/// in relative frets (any octave, possibly below the nut), then placed at the lowest fret where
/// they fit wholly between the capo and the last fret, plus an octave-up copy when that fits too.
extension Fretboard {
    /// The placements of a position given in relative frets: the lowest that fits, then the
    /// octave-up copy if it fits. Empty when it fits nowhere (a high capo).
    func placements(of relativeLocations: [FretboardLocation]) -> [[FretboardLocation]] {
        guard let low = relativeLocations.map(\.fret).min(), let high = relativeLocations.map(\.fret).max()
        else { return [] }
        // The smallest octave shift that lifts the lowest fret to the capo or above.
        let lowest = Int((Double(playableFrets.lowerBound - low) / 12).rounded(.up))
        return [lowest, lowest + 1]
            .filter { high + 12 * $0 <= playableFrets.upperBound }
            .map { shift in
                relativeLocations.map { FretboardLocation(string: $0.string, fret: $0.fret + 12 * shift) }
            }
    }

    /// `notesPerString` scale notes per string from string 6 up, starting on `notes[start]`,
    /// in relative frets. Each string's first note sits nearest the previous string's first
    /// note, which keeps the walk compact in any tuning (and is the plain pitch walk in rising
    /// ones). CAGED shapes walk the pentatonic two per string; 3NPS patterns the scale three.
    func walk(_ notes: [PitchClass], from start: Int, notesPerString: Int) -> [FretboardLocation] {
        var locations: [FretboardLocation] = []
        var anchor: Int?
        for string in strings {
            let index = start + notesPerString * (string - strings.lowerBound)
            let first = relativeFret(of: notes[index % notes.count], onString: string, near: anchor)
            var fret = first
            locations.append(FretboardLocation(string: string, fret: fret))
            for step in 1..<notesPerString {
                let previous = notes[(index + step - 1) % notes.count]
                fret += previous.interval(upTo: notes[(index + step) % notes.count]).semitones
                locations.append(FretboardLocation(string: string, fret: fret))
            }
            anchor = first
        }
        return locations
    }

    /// The relative fret of a pitch class on a string nearest to `anchor` (ties go lower);
    /// with no anchor, the lowest fret 0–11.
    func relativeFret(of pitchClass: PitchClass, onString string: Int, near anchor: Int?) -> Int {
        let open = tuning.openPitch(ofString: string).pitchClass
        let base = open.interval(upTo: pitchClass).semitones
        guard let anchor else { return base }
        let up = (base - anchor % 12 + 24) % 12
        return up < 6 ? anchor + up : anchor + up - 12
    }
}

extension Fretboard {
    /// Where to play a scale near a position of another: the same shape or pattern, in its nearest placement, or where
    /// the scale has none of that system, the nearest CAGED shape. Nearest by lowest fret, ties to the lower. Nil if
    /// there is none on the neck.
    public func position(of scale: Scale, nearest position: Position) -> Position? {
        let candidates = position.system == .threeNotesPerString && !scale.kind.isSevenNote
            ? cagedPositions(of: scale)
            : positions(of: scale, system: position.system).filter { $0.number == position.number }
        // They come up the neck, and the first of equals is kept.
        return candidates.min { $0.distance(from: position) < $1.distance(from: position) }
    }
}

extension Position {
    fileprivate func distance(from other: Position) -> Int { abs(frets.lowerBound - other.frets.lowerBound) }
}

extension Array where Element == Position {
    /// Ordered up the neck: by lowest fret, then CAGED shape or 3NPS pattern number.
    func sortedUpTheNeck() -> [Position] {
        sorted { ($0.frets.lowerBound, $0.number) < ($1.frets.lowerBound, $1.number) }
    }
}

extension Array where Element == FretboardLocation {
    /// The frets covered, lowest to highest (open strings count as fret 0). The array must not be empty.
    var fretSpan: ClosedRange<Int> {
        let frets = map(\.fret)
        return frets.min()!...frets.max()!
    }
}
