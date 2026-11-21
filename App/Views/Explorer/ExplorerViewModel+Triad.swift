import TheoryCore

/// What the inversion picker selects: every inversion at once, or one.
enum InversionChoice: Hashable {
    case all
    case single(Triad.Inversion)

    var inversions: [Triad.Inversion] {
        switch self {
        case .all: Triad.Inversion.allCases
        case .single(let inversion): [inversion]
        }
    }

    /// "All inversions", "Root position", "1st inversion", …
    var name: String {
        switch self {
        case .all: "All inversions"
        case .single(let inversion): inversion.name
        }
    }
}

/// Triad mode: the key's triad on the chosen string set and inversion(s), every voicing along the neck.
extension ExplorerViewModel {
    /// The key's tonic triad; its quality is the shared major/minor `mode` (A minor triad).
    var triad: Triad { key.triad }

    /// Every voicing of the triad on the chosen string set, for each chosen inversion, up the neck.
    var triadVoicings: [TriadVoicing] {
        let fretboard = fretboard
        let triad = triad
        return inversionChoice.inversions.flatMap { fretboard.voicings(of: triad, inversion: $0, on: stringSet) }
    }

    /// The string sets the picker offers (the UI is fixed at six strings).
    var stringSets: [StringSet] { fretboard.stringSets }

    /// Triad mode's header, chips, legend label and markers (one dot per location, deduplicated
    /// where voicings share a fret, as they do when all inversions are shown).
    var triadMode: Mode {
        let fretboard = fretboard
        let triad = triad
        let voicings = triadVoicings
        let count = voicings.count
        var seen = Set<FretboardLocation>()
        return Mode(
            title: "\(triad.name) triad",
            detail: "\(stringSet.name) strings · \(inversionChoice.name) · \(count) voicing\(count == 1 ? "" : "s")",
            chips: triad.notes.map { Chip(name: $0.description, isRoot: $0 == triad.root) },
            toneLabel: "Chord tone",
            markers: voicings.flatMap(\.locations).filter { seen.insert($0).inserted }.map { location in
                let name = fretboard.name(at: location, in: key)
                return .init(location: location, label: name.description, role: name == triad.root ? .root : .tone)
            })
    }
}
