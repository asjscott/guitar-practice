import TheoryCore

/// What the position picker selects: the whole neck, or one position by its stable ID
/// (system, shape number, octave), so the choice survives key, scale, tuning and capo changes.
enum PositionChoice: Hashable {
    case wholeNeck
    case position(Position.ID)

    /// The explorer opens on the CAGED E shape.
    static let initial = PositionChoice.position(Position.ID(system: .caged, number: CAGEDShape.e.number))
}

/// The scale display's position: which positions exist, which one is shown, and the header text.
extension ExplorerViewModel {
    /// The positions on offer for the current scale, ordered up the neck.
    /// #8: choose CAGED or 3NPS here from the position-system setting.
    var positions: [Position] { fretboard.cagedPositions(of: scale) }

    /// The position shown, or nil for the whole neck. When the chosen placement no longer fits
    /// (for example its octave-up copy after a key change), falls back to the same shape's
    /// lowest placement, then to the whole neck.
    var position: Position? {
        guard case .position(let id) = positionChoice else { return nil }
        let positions = positions
        return positions.first { $0.id == id }
            ?? positions.first { $0.system == id.system && $0.number == id.number && $0.octave == 0 }
    }

    /// The picker's selection: always one of `positionOptions`.
    var selectedPosition: PositionChoice {
        get { position.map { .position($0.id) } ?? .wholeNeck }
        set { positionChoice = newValue }
    }

    /// The picker's entries after "Whole neck", up the neck.
    var positionOptions: [(choice: PositionChoice, label: String)] {
        positions.map { (.position($0.id), $0.octave == 0 ? $0.name : "\($0.name) (octave up)") }
    }

    /// The scale's locations on the neck: the chosen position's, or every one.
    var scaleLocations: [FretboardLocation] {
        position?.locations ?? fretboard.locations(of: scale)
    }

    /// Header detail in scale mode, for example "E shape · frets 7–10".
    var scaleDetail: String {
        guard let position else { return "Whole neck · \(fretboard.locations(of: scale).count) locations" }
        return "\(position.name) · frets \(position.frets.lowerBound)–\(position.frets.upperBound)"
    }
}
