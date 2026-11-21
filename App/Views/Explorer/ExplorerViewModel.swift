import Observation
import TheoryCore

/// State and derived content for the fretboard explorer window.
///
/// Holds the picker state (not persisted) and turns it, plus the instrument setup, into what
/// the window shows by asking TheoryCore. It does no note or fret maths of its own.
///
/// Extension points for later tickets:
/// - `tuning` becomes the persisted tuning (and a capo joins it) from Settings (#4).
/// - Position (#7/#8), triad (#9) and label-mode (#6) state join `key`, `display` and `scaleKind`.
/// - `diagram`, `title`, `detail`, `chips` and `legend` are the only things the view reads;
///   new modes change what they return, not how the view draws.
@MainActor @Observable
final class ExplorerViewModel {
    /// What the neck shows: a scale, or a triad (triads arrive with #9).
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

    // MARK: Picker state (opens on C major every time)

    /// One of `Key.appMajorKeys`; minor scales use its relative minor.
    var key: Key = .major(.c)
    var display: Display = .scale
    var scaleKind: Scale.Kind = .major

    /// The keys the key picker offers.
    let keys = Key.appMajorKeys

    // MARK: Display options (labels, debug heatmap; see ExplorerViewModel+Display.swift)

    var labelMode: FretboardDiagram.LabelMode = .shown

    /// Debug: fill the heatmap with random values. Off by default; Phase 0 has no real data.
    var showsDebugHeatmap = false

    /// Seed for the debug heatmap's random values; shuffling picks a new one.
    var debugHeatSeed = UInt64.random(in: .min ... .max)

    // MARK: Instrument

    var tuning: Tuning = .standard

    var fretboard: Fretboard { Fretboard(tuning: tuning) }

    // MARK: Theory

    /// The chosen scale in the chosen key (minor kinds start on the key's relative minor).
    var scale: Scale { Scale(scaleKind, in: key) }

    // MARK: What the window shows

    var diagram: FretboardDiagram {
        let fretboard = fretboard
        let scale = scale
        let markers: [FretboardDiagram.Marker] = switch display {
        case .scale:
            fretboard.locations(of: scale).map { location in
                let name = fretboard.name(at: location, in: scale)
                return .init(location: location, label: name.description,
                             role: name == scale.tonic ? .root : .tone)
            }
        case .triad:
            [] // #9: triad voicings.
        }
        return FretboardDiagram(
            stringNames: fretboard.stringNames(in: scale.key).map(\.description),
            lastFret: Fretboard.frets.upperBound,
            markers: markers)
    }

    var title: String {
        switch display {
        case .scale: scale.name
        case .triad: "\(key) triad"
        }
    }

    var detail: String {
        switch display {
        case .scale: "Whole neck · \(fretboard.locations(of: scale).count) locations"
        case .triad: "Triad voicings are not available yet"
        }
    }

    var chips: [Chip] {
        switch display {
        case .scale: scale.notes.map { Chip(name: $0.description, isRoot: $0 == scale.tonic) }
        case .triad: []
        }
    }

    var legend: [LegendItem] {
        switch display {
        case .scale: [LegendItem(role: .root, label: "Root"), LegendItem(role: .tone, label: "Scale tone")]
        case .triad: [LegendItem(role: .root, label: "Root"), LegendItem(role: .tone, label: "Chord tone")]
        }
    }
}
