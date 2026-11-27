import Foundation

extension Fretboard {
    /// The Scale circle's positions (GLOSSARY.md): the theme's scale in the theme's position, then the same scale in
    /// each next key round the circle of fifths, each in the position of the same system nearest where the last pass
    /// ended. Passes take turns going up and down, the first going `direction`. Twelve, unless a key has no root in
    /// range that a position holds, where it stops (the probe in #64 found none in any app key, position or tuning).
    ///
    /// - **Range**: the theme's frets, for the whole circle. If they touch the capo fret or either of the two above it,
    ///   the circle starts from the theme's octave-up copy and the range moves up 12 with it, unless that is off the neck.
    /// - **Roots**: the next key's roots inside the range that some position of the same system holds.
    /// - **Choice**: the root closest in pitch to the last pass's end note (its top going up, its bottom going down),
    ///   then the lower fret.
    /// - **Position**: of the positions holding that root, the one overlapping the range most, then the lower one.
    public func scaleCirclePositions(from theme: Position, going direction: PassDirection) -> [Position] {
        let first = theme.frets.lowerBound <= capo + 2 ? octaveUp(of: theme) ?? theme : theme
        let range = first.frets
        var circle = [first]
        var direction = direction
        for key in theme.scale.key.circleOfFifths.dropFirst() {
            guard let last = circle.last,
                  let next = position(of: Scale(theme.scale.kind, in: key), system: first.system, in: range,
                                      after: last, going: direction) else { break }
            circle.append(next)
            direction = direction.reversed
        }
        return circle
    }

    /// The same position an octave up, if it fits the neck.
    private func octaveUp(of position: Position) -> Position? {
        positions(of: position.scale, system: position.system).first {
            $0.number == position.number && $0.octave == position.octave + 1
        }
    }

    /// The next pass's position, after a pass through `last` going `direction`.
    private func position(of scale: Scale, system: Position.System, in range: ClosedRange<Int>, after last: Position,
                          going direction: PassDirection) -> Position? {
        let pitches = last.locations.map(pitch)
        guard let end = direction == .up ? pitches.max() : pitches.min() else { return nil }
        let positions = positions(of: scale, system: system)
        let roots = locations(of: scale.tonic.pitchClass).filter { root in
            range.contains(root.fret) && positions.contains { $0.locations.contains(root) }
        }
        func distance(_ root: FretboardLocation) -> (Int, Int) { (abs((pitch(at: root) - end).semitones), root.fret) }
        guard let root = roots.min(by: { distance($0) < distance($1) }) else { return nil }
        func overlap(_ position: Position) -> Int {
            max(0, min(position.frets.upperBound, range.upperBound) - max(position.frets.lowerBound, range.lowerBound) + 1)
        }
        // They come up the neck: the first of equals is the lower.
        return positions.filter { $0.locations.contains(root) }.reduce(nil) { best, position in
            guard let best else { return position }
            return overlap(position) > overlap(best) ? position : best
        }
    }
}
