import Observation
import TheoryCore

/// State and derived content for the fretboard explorer window.
///
/// Holds the picker state (not persisted) and turns it, plus the instrument setup, into what
/// the window shows by asking TheoryCore. It does no note or fret maths of its own.
///
/// The view reads `content` (worked out once per render: header, chips, legend and diagram),
/// `windowSubtitle` and the picker state. A new mode adds a case to `Display` and its own
/// `Mode`; the view's drawing doesn't change.
@MainActor @Observable
final class ExplorerViewModel {
    /// What the neck shows: a scale, or the key's triad.
    enum Display: String, CaseIterable, Identifiable {
        case scale = "Scale"
        case triad = "Triad"
        var id: Self { self }
    }

    /// A note chip in the header.
    struct Chip: Hashable {
        var name: String
        var isRoot: Bool
    }

    /// One entry of the status-bar legend.
    struct LegendItem: Hashable {
        var role: FretboardDiagram.Role
        var label: String
    }

    /// Everything the window shows for the current mode.
    struct Content {
        var title: String
        var detail: String
        var chips: [Chip]
        var legend: [LegendItem]
        /// The markers plus the display options (labels, heat).
        var diagram: FretboardDiagram
    }

    // MARK: Picker state (opens on C major every time)

    /// The key picker's tonic. The mode comes from the scale kind, so switching between
    /// major and minor scales keeps the pitch class (D♭ major → C♯ minor).
    var tonic: PitchClass = Key.major(.c).tonic.pitchClass
    var display: Display = .scale
    var scaleKind: Scale.Kind = .major
    /// The position picker's choice (see ExplorerViewModel+Position.swift); opens on the E shape.
    var positionChoice: PositionChoice = .initial

    /// Triad mode (see ExplorerViewModel+Triad.swift).
    var stringSet: StringSet = .gBE
    var inversionChoice: InversionChoice = .all

    /// Major or minor, shared by both displays: the scale kind's mode, which is also the
    /// triad's quality. Setting it moves the scale kind to its counterpart in that mode
    /// (major ↔ natural minor, pentatonics swap, blues → major pentatonic) and keeps the
    /// tonic pitch class, so the key picker relabels (D♭ major → C♯ minor).
    var mode: Key.Mode {
        get { scaleKind.mode }
        set { scaleKind = scaleKind.inMode(newValue) }
    }

    /// The keys the key picker offers, in the current mode (labelled by tonic: C G D … / A E B …).
    var keys: [Key] { Key.appKeys(scaleKind.mode) }

    // MARK: Display options (labels, debug heatmap; see ExplorerViewModel+Display.swift)

    var labelMode: FretboardDiagram.LabelMode = .shown

    /// Debug: fill the heatmap with random values. Off by default; Phase 0 has no real data.
    var showsDebugHeatmap = false

    /// Seed for the debug heatmap's random values; shuffling picks a new one.
    var debugHeatSeed = UInt64.random(in: .min ... .max)

    // MARK: Instrument

    /// Set from the persisted Settings (see `ContentView`).
    var tuning: Tuning = .standard
    var capo: Int = 0
    /// CAGED or 3NPS; pentatonic and blues always get CAGED shapes (TheoryCore decides).
    var positionSystem: Position.System = .caged

    var fretboard: Fretboard { Fretboard(tuning: tuning, capo: capo) }

    // MARK: Theory

    /// The chosen key: the picked tonic in the scale kind's mode (A + natural minor → A minor).
    var key: Key { Key.app(tonic: tonic, mode: scaleKind.mode) }

    /// The chosen scale, built on the key's tonic.
    var scale: Scale { Scale(scaleKind, in: key) }

    // MARK: What the window shows

    var content: Content {
        let mode = switch display {
        case .scale: scaleMode
        case .triad: triadMode
        }
        return Content(title: mode.title, detail: mode.detail, chips: mode.chips,
                       legend: [LegendItem(role: .root, label: "Root"), LegendItem(role: .tone, label: mode.toneLabel)],
                       diagram: diagram(markers: mode.markers))
    }

    /// The window subtitle, as in the A2 prototype: "Drop D tuning · capo 2" (no capo part
    /// without a capo; "Custom tuning" when the tuning is not a preset).
    var windowSubtitle: String {
        tuning.displayName + (capo > 0 ? " · capo \(capo)" : "")
    }

    /// One mode's share of `content`: the legend differs only in what a non-root dot is.
    struct Mode {
        var title: String
        var detail: String
        var chips: [Chip]
        var toneLabel: String
        var markers: [FretboardDiagram.Marker]
    }

    private var scaleMode: Mode {
        let fretboard = fretboard
        let scale = scale
        return Mode(
            title: scale.name,
            detail: scaleDetail,
            chips: scale.notes.map { Chip(name: $0.description, isRoot: $0 == scale.tonic) },
            toneLabel: "Scale tone",
            markers: scaleLocations.map { location in
                let name = fretboard.name(at: location, in: scale)
                return .init(location: location, label: name.description, role: name == scale.tonic ? .root : .tone)
            })
    }

    /// The neck with the given markers, string names spelled in the scale's key, and the
    /// display options applied.
    private func diagram(markers: [FretboardDiagram.Marker]) -> FretboardDiagram {
        let fretboard = fretboard
        return FretboardDiagram(
            stringNames: fretboard.stringNames(in: scale.key).map(\.description),
            lastFret: Fretboard.frets.upperBound,
            capo: fretboard.capo,
            markers: markers,
            labelMode: labelMode,
            heat: heat)
    }
}
