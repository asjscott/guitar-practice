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

    /// Triad mode's header, chips, legend label and markers (one dot per location, deduplicated
    /// where voicings share a fret).
    var triadMode: Mode {
        let fretboard = fretboard
        let triad = triad
        let voicings = triadVoicings
        let count = voicings.count
        var seen = Set<FretboardLocation>()
        return Mode(
            title: "\(triad.name) triad",
            detail: "\(stringSet.name) strings · \(inversion.name) · \(count) voicing\(count == 1 ? "" : "s")",
            chips: triad.notes.map { Chip(name: $0.description, isRoot: $0 == triad.root) },
            toneLabel: "Chord tone",
            markers: voicings.flatMap(\.locations).filter { seen.insert($0).inserted }.map { location in
                let name = fretboard.name(at: location, in: key)
                return .init(location: location, label: name.description, role: name == triad.root ? .root : .tone)
            })
    }
}
