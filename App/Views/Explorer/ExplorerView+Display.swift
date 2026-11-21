import SwiftUI

/// The explorer's display controls: the label control and debug menu in the toolbar, and the
/// heat legend in the status bar.
extension ExplorerView {
    @ToolbarContentBuilder
    var displayToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Labels", selection: $model.labelMode) {
                Image(systemName: "textformat").tag(FretboardDiagram.LabelMode.shown)
                    .help("Note names")
                Image(systemName: "textformat.alt").tag(FretboardDiagram.LabelMode.faded)
                    .help("Faded names")
                Image(systemName: "circle.fill").tag(FretboardDiagram.LabelMode.hidden)
                    .help("Dots only")
            }
            .pickerStyle(.segmented)
            .help("Note labels")

            Menu {
                Toggle("Heatmap Overlay", isOn: $model.showsDebugHeatmap)
                Button("Shuffle Heatmap Values") { model.shuffleDebugHeat() }
                    .disabled(!model.showsDebugHeatmap)
            } label: {
                Label("Debug", systemImage: "ladybug")
            }
            .help("Debug")
        }
    }

    /// A small gradient key for the heatmap tint, shown while the overlay is on.
    @ViewBuilder
    var heatLegend: some View {
        if model.showsDebugHeatmap {
            HStack(spacing: 6) {
                Text("Low")
                LinearGradient(colors: FretboardPalette.heatLegendStops, startPoint: .leading, endPoint: .trailing)
                    .frame(width: 48, height: 6)
                    .clipShape(Capsule())
                Text("High")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Heatmap (debug: random values)")
        }
    }
}
