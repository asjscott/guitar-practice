import Foundation

/// Which way a one-way pass goes: by pitch, up from the position's lowest note or down from its highest. The raw values
/// are saved in the attempt log: never change them.
public enum PassDirection: String, Hashable, Sendable, CaseIterable {
    case up, down

    /// The other way: a circle's passes take turns.
    public var reversed: PassDirection { self == .up ? .down : .up }
}

extension Fretboard {
    /// The locations of a pass through a position: up from the lowest location of the start degree to the top, down to
    /// the bottom and back to the start, the top once. Ordered by pitch, each pitch once each way; one that appears
    /// twice in the position is played on the lower string. Nil if the position lacks the degree.
    public func passOrder(of position: Position, from degree: Scale.Degree) -> [FretboardLocation]? {
        let rising = risingByPitch(position)
        guard let start = rising.firstIndex(where: { position.scale.degree(of: $0.key.pitchClass) == degree }) else { return nil }
        let locations = rising.map(\.value)
        return Array(locations[start...]) + locations.dropLast().reversed() + locations[...start].dropFirst()
    }

    /// The locations of a one-way pass through a position: from its lowest note to its highest, or back. By pitch, each
    /// pitch once, on the lower string where the position has it twice.
    public func passOrder(of position: Position, going direction: PassDirection) -> [FretboardLocation] {
        let up = risingByPitch(position).map(\.value)
        return direction == .up ? up : up.reversed()
    }

    private func risingByPitch(_ position: Position) -> [(key: Pitch, value: FretboardLocation)] {
        // Locations are string 6 first, so the first of a pitch is on the lower string.
        let byPitch = Dictionary(position.locations.map { (pitch(at: $0), $0) }, uniquingKeysWith: { first, _ in first })
        return byPitch.sorted { $0.key < $1.key }
    }
}
