import Foundation

/// Placement shared by every position system (ADR-0001): a shape is generated in relative
/// frets (any octave, possibly below the nut), then placed at the lowest fret where it fits
/// wholly between the capo and the last fret, plus its octave-up copy when that fits too.
extension Fretboard {
    /// The placements of a shape given in relative frets: the lowest that fits, then the
    /// octave-up copy if it fits. Empty when the shape fits nowhere (a high capo).
    func placements(ofShape shape: [FretboardLocation]) -> [[FretboardLocation]] {
        guard let low = shape.map(\.fret).min(), let high = shape.map(\.fret).max() else { return [] }
        // The smallest octave shift that lifts the lowest fret to the capo or above.
        let lowest = Int((Double(playableFrets.lowerBound - low) / 12).rounded(.up))
        return [lowest, lowest + 1]
            .filter { high + 12 * $0 <= playableFrets.upperBound }
            .map { shift in shape.map { FretboardLocation(string: $0.string, fret: $0.fret + 12 * shift) } }
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
