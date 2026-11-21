import TheoryCore

/// Everything the fretboard view draws, already worked out by TheoryCore.
///
/// The view does no note maths: it only places what it is given. Callers (the explorer view
/// model today, exercises later) build a diagram by asking TheoryCore. New drawing features
/// add a field here with a default, so existing call sites keep compiling.
struct FretboardDiagram: Equatable {
    /// What a dot means, which picks its colour.
    enum Role: Hashable {
        case root
        case tone
    }

    /// Note labels: names, faded names (about 30% opacity) or dots only.
    enum LabelMode: String, CaseIterable, Hashable, Identifiable {
        case shown
        case faded
        case hidden

        var id: Self { self }
    }

    /// A dot on the neck at one fretboard location, with its (already spelled) label.
    struct Marker: Hashable {
        var location: FretboardLocation
        var label: String
        var role: Role
    }

    /// One name per string, string 6 first (index 0 = physical string 6, drawn at the bottom).
    var stringNames: [String]

    /// The last fret drawn; the neck always runs from the nut to this fret.
    var lastFret: Int = Fretboard.frets.upperBound

    /// The capo fret (0 = none). Drawn as a bar with the frets below it dimmed; fret numbers
    /// still count from the nut.
    var capo: Int = 0

    var markers: [Marker] = []

    /// How dot labels are drawn. The dots themselves stay in every mode.
    var labelMode: LabelMode = .shown

    /// Optional heatmap: a value from 0 to 1 per fretboard location, drawn as an amber-to-red
    /// tint behind that location. `nil` draws no tint. Callers pass only playable locations.
    var heat: [FretboardLocation: Double]? = nil

    var stringCount: Int { stringNames.count }

    /// Whether a location is on the drawn neck (one of its strings, nut to `lastFret`);
    /// markers and heat elsewhere are skipped.
    func draws(_ location: FretboardLocation) -> Bool {
        (0..<stringCount).contains(location.string) && (0...lastFret).contains(location.fret)
    }
}
