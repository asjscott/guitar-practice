import TheoryCore

/// Triad mode: the key's triad on the chosen string set and inversion, every voicing along the neck.
extension ExplorerViewModel {
    /// The key's tonic triad (the key picker offers major keys, so this is a major triad).
    var triad: Triad { key.triad }

    /// Every voicing of the triad on the chosen string set and inversion, up the neck.
    var triadVoicings: [TriadVoicing] {
        fretboard.voicings(of: triad, inversion: inversion, on: stringSet)
    }

    /// The string sets the picker offers (the UI is fixed at six strings).
    var stringSets: [StringSet] { fretboard.stringSets }

    var triadMarkers: [FretboardDiagram.Marker] {
        let fretboard = fretboard
        let triad = triad
        var seen = Set<FretboardLocation>()
        return triadVoicings.flatMap(\.locations).filter { seen.insert($0).inserted }.map { location in
            let name = fretboard.name(at: location, in: key)
            return .init(location: location, label: name.description, role: name == triad.root ? .root : .tone)
        }
    }

    var triadTitle: String { "\(triad.name) triad" }

    var triadDetail: String {
        let count = triadVoicings.count
        return "\(stringSet.name) strings · \(inversion.name) · \(count) voicing\(count == 1 ? "" : "s")"
    }

    var triadChips: [Chip] {
        triad.notes.map { Chip(name: $0.description, isRoot: $0 == triad.root) }
    }
}
