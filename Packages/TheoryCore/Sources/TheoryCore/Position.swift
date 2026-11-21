import Foundation

/// A playable region of the neck holding one scale in one key: a CAGED shape or a 3NPS pattern
/// (see GLOSSARY.md), placed at a particular fret window.
///
/// Positions come from `Fretboard` (for example `cagedPositions(of:)`), already placed between
/// the capo and the last fret, so their locations are always playable.
public struct Position: Hashable, Sendable, Identifiable {
    /// The two kinds of position.
    public enum System: String, Hashable, Sendable, Codable, CaseIterable {
        /// Five CAGED shapes per key (Position 1–5), for every scale.
        case caged
        /// Seven 3NPS patterns per key, for seven-note scales only.
        case threeNotesPerString
    }

    /// Which position this is, stable across keys, tunings and capo: the system, the CAGED shape or
    /// 3NPS pattern number, and which placement (0 = lowest, 1 = an octave higher).
    public struct ID: Hashable, Sendable, Codable {
        public let system: System
        /// CAGED: 1–5 (E D C A G); 3NPS: 1–7.
        public let number: Int
        /// 0 = the lowest placement that fits; 1 = its octave-up copy.
        public let octave: Int

        public init(system: System, number: Int, octave: Int = 0) {
            self.system = system
            self.number = number
            self.octave = octave
        }
    }

    public let id: ID

    /// The scale whose notes the position holds.
    public let scale: Scale

    /// For example "E shape", or "Position 1" where CAGED names don't apply.
    public let name: String

    /// The CAGED shape, for CAGED positions; nil for 3NPS patterns.
    public let cagedShape: CAGEDShape?

    /// Every location in the position, string 6 first, then by fret.
    public let locations: [FretboardLocation]

    init(id: ID, scale: Scale, name: String, cagedShape: CAGEDShape? = nil, locations: [FretboardLocation]) {
        precondition(!locations.isEmpty, "A position holds at least one location")
        self.id = id
        self.scale = scale
        self.name = name
        self.cagedShape = cagedShape
        self.locations = locations.sorted { ($0.string, $0.fret) < ($1.string, $1.fret) }
    }

    public var system: System { id.system }
    public var number: Int { id.number }
    public var octave: Int { id.octave }

    /// The fret window: lowest to highest fret used.
    public var frets: ClosedRange<Int> {
        let frets = locations.map(\.fret)
        return frets.min()!...frets.max()!
    }
}
