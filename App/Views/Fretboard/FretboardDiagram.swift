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
        /// Drawn faintly, without its label.
        var isFaint = false
        /// Ringed as the last note played.
        var isLastPlayed = false
        /// PROTOTYPE (Phase 4b): how much of the dot is left, for the fade by time.
        var opacity: Double = 1
    }

    /// One name per string, string 6 first (index 0 = physical string 6, drawn at the bottom).
    var stringNames: [String]

    /// The last fret of the neck, which runs from the nut to this fret.
    var lastFret: Int = Fretboard.frets.upperBound

    /// The frets to zoom in on, with a thin bar showing which part of the neck they are. `nil`, or the whole neck,
    /// draws the whole neck without one.
    var fretWindow: ClosedRange<Int>? = nil

    /// The capo fret (0 = none). Drawn as a bar with the frets below it dimmed; fret numbers
    /// still count from the nut.
    var capo: Int = 0

    var markers: [Marker] = []

    /// How dot labels are drawn. The dots themselves stay in every mode.
    var labelMode: LabelMode = .shown

    /// Optional heatmap: a value from 0 to 1 per fretboard location, drawn as an amber-to-red
    /// tint behind that location. `nil` draws no tint. Callers pass only playable locations.
    var heat: [FretboardLocation: Double]? = nil

    /// Strings to highlight with a band along their length (internal index, 0 = string 6), such as a drill's target
    /// string or a string set.
    var highlightedStrings: Set<Int> = []

    var stringCount: Int { stringNames.count }

    /// The frets drawn.
    var frets: ClosedRange<Int> { (fretWindow ?? 0...lastFret).clamped(to: 0...lastFret) }

    var isZoomed: Bool { frets != 0...lastFret }

    /// Whether a location is on the drawn neck (one of its strings, in `frets`);
    /// markers and heat elsewhere are skipped.
    func draws(_ location: FretboardLocation) -> Bool {
        (0..<stringCount).contains(location.string) && frets.contains(location.fret)
    }
}
