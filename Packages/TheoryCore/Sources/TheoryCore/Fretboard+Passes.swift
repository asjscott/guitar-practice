import Foundation

extension Fretboard {
    /// The locations of a pass through a position: up from the lowest location of the start degree to the top, down to
    /// the bottom and back to the start, the top once. Ordered by pitch, each pitch once each way; one that appears
    /// twice in the position is played on the lower string. Nil if the position lacks the degree.
    public func passOrder(of position: Position, from degree: Scale.Degree) -> [FretboardLocation]? {
        // Locations are string 6 first, so the first of a pitch is on the lower string.
        let byPitch = Dictionary(position.locations.map { (pitch(at: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let rising = byPitch.sorted { $0.key < $1.key }
        guard let start = rising.firstIndex(where: { position.scale.degree(of: $0.key.pitchClass) == degree }) else { return nil }
        let locations = rising.map(\.value)
        return Array(locations[start...]) + locations.dropLast().reversed() + locations[...start].dropFirst()
    }
}
