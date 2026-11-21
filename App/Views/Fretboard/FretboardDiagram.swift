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

    var markers: [Marker] = []

    var stringCount: Int { stringNames.count }
}
