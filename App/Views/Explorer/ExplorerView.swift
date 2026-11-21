import SwiftUI
import TheoryCore

/// The main window: the fretboard explorer in the A2 layout.
///
/// Pickers live in the native window toolbar; a header names what is on the neck with the
/// notes as chips; the fretboard sits in a rounded card; a status bar holds the legend.
/// The view is thin: everything it shows comes from `ExplorerViewModel`.
struct ExplorerView: View {
    @Bindable var model: ExplorerViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 14)

            FretboardView(diagram: model.displayedDiagram)
                .frame(height: 250)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
                .padding(.horizontal, 24)

            Spacer(minLength: 16)
            Divider()
            statusBar
                .padding(.horizontal, 24)
                .frame(height: 32)
                .background(.bar)
        }
        .navigationTitle("Fretboard")
        .toolbar { toolbar }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title).font(.system(size: 26, weight: .semibold))
                Text(model.detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Array(model.chips.enumerated()), id: \.offset) { _, chip in
                    Text(chip.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(minWidth: 26, minHeight: 22)
                        .background(Capsule().fill(chip.isRoot
                            ? FretboardPalette.root.opacity(0.18)
                            : Color.secondary.opacity(0.12)))
                        .foregroundStyle(chip.isRoot ? FretboardPalette.root : .primary)
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Picker("Key", selection: $model.key) {
                ForEach(model.keys, id: \.self) { Text($0.shortName).tag($0) }
            }
            .help("Key")

            Picker("Show", selection: $model.display) {
                ForEach(ExplorerViewModel.Display.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Show a scale or a triad")
        }

        ToolbarItemGroup(placement: .principal) {
            if model.display == .scale {
                Picker("Scale", selection: $model.scaleKind) {
                    ForEach(Scale.Kind.allCases, id: \.self) { Text($0.name.capitalizedFirst).tag($0) }
                }
                .help("Scale")

                Picker("Position", selection: $model.selectedPosition) {
                    Text("Whole neck").tag(PositionChoice.wholeNeck)
                    Divider()
                    ForEach(model.positionOptions, id: \.choice) { Text($0.label).tag($0.choice) }
                }
                .help("Position")
            }
        }

        triadToolbar
        displayToolbar
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            ForEach(model.legend, id: \.self) { item in
                HStack(spacing: 6) {
                    Circle().fill(FretboardPalette.color(for: item.role)).frame(width: 9, height: 9)
                    Text(item.label).foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            heatLegend
            Spacer()
        }
        .font(.callout)
    }
}

private extension String {
    /// "natural minor" → "Natural minor", for picker labels.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

#Preview {
    ExplorerView(model: ExplorerViewModel())
        .frame(width: 900, height: 420)
}
