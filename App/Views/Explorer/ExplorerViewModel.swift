import Observation
import TheoryCore

/// State and derived content for the fretboard explorer window.
///
/// Holds the picker state (not persisted) and turns it, plus the instrument setup, into what
/// the window shows by asking TheoryCore. It does no note or fret maths of its own.
///
/// Extension points for later tickets:
/// - `key` becomes TheoryCore's `Key`; scale, position, triad and label-mode state join it (#5–#9).
/// - `diagram`, `title`, `detail`, `chips` and `legend` are the only things the view reads;
///   new modes change what they return, not how the view draws.
@MainActor @Observable
final class ExplorerViewModel {
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

    // MARK: Picker state (opens on C every time)

    var key: ExplorerKeyChoice = .c

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

    var fretboard: Fretboard { Fretboard(tuning: tuning, capo: capo) }

    // MARK: What the window shows

    /// Every location of the key's tonic, labelled with sharps (no key-aware spelling yet).
    var diagram: FretboardDiagram {
        let fretboard = fretboard
        return FretboardDiagram(
            stringNames: tuning.openPitches.map(\.pitchClass.sharpName),
            lastFret: Fretboard.frets.upperBound,
            capo: fretboard.capo,
            markers: fretboard.locations(of: key.tonic).map { location in
                .init(location: location, label: fretboard.pitch(at: location).pitchClass.sharpName, role: .root)
            })
    }

    var title: String { "\(key.name) major" }

    var detail: String {
        let count = fretboard.locations(of: key.tonic).count
        return "Every \(key.name) on the neck · \(count) locations"
    }

    var chips: [Chip] { [Chip(name: key.name, isRoot: true)] }

    var legend: [LegendItem] { [LegendItem(role: .root, label: "Root")] }
}
