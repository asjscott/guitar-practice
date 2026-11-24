import TheoryCore

extension FretboardDiagram.Marker {
    /// A note of a scale, spelled in it.
    init(_ location: FretboardLocation, of scale: Scale, on fretboard: Fretboard) {
        let name = fretboard.name(at: location, in: scale)
        self.init(location: location, label: name.description, role: name == scale.tonic ? .root : .tone)
    }
}

extension FretboardDiagram {
    /// A position on a whole neck, its notes named. `key` spells the string names.
    init(_ position: Position, in key: Key, on fretboard: Fretboard) {
        self.init(stringNames: fretboard.stringNames(in: key).map(\.description), capo: fretboard.capo,
                  markers: position.locations.map { Marker($0, of: position.scale, on: fretboard) })
    }
}
