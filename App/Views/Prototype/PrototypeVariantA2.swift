// PROTOTYPE — throwaway. Variant A2: variant A's layout (fretboard first, controls in one strip),
// made native: controls move into the window toolbar, a header names what's on the neck,
// the board sits in a card, and instrument + legend live in a status bar.

import SwiftUI

#if DEBUG
struct VariantA2: View {
    @Bindable var model: PrototypeExplorerModel

    private let rootColor = Color(red: 0.91, green: 0.45, blue: 0.23)
    private let toneColor = Color(red: 0.23, green: 0.51, blue: 0.96)

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)

            PrototypeFretboard(model: model)
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
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 26, weight: .semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Array(noteNames.enumerated()), id: \.offset) { i, n in
                    Text(n)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(minWidth: 26, minHeight: 22)
                        .background(Capsule().fill(i == 0 ? rootColor.opacity(0.18) : Color.secondary.opacity(0.12)))
                        .foregroundStyle(i == 0 ? rootColor : .primary)
                }
            }
        }
    }

    private var title: String {
        model.display == .scale
            ? "\(model.keyTitle) \(model.scale.rawValue.lowercased())"
            : "\(model.keyTitle) \(model.scale.isMinor ? "minor" : "major") triad"
    }

    private var detail: String {
        if model.display == .triad {
            return "\(protoInversions[model.inversion]) inversion on \(protoStringSets[model.stringSet]) · \(model.triadVoicings.count) voicings"
        }
        guard let i = model.positionIndex, model.positions.indices.contains(i) else {
            return "Whole neck · \(model.effectiveSystem.rawValue)"
        }
        let p = model.positions[i]
        return "\(p.name) · frets \(p.minFret)–\(p.maxFret)"
            + (model.scale.isSevenNote || model.system == .caged ? "" : " · 3NPS needs a seven-note scale")
    }

    private var subtitle: String { "\(model.tuning.name) tuning" + (model.capo > 0 ? " · capo \(model.capo)" : "") }

    private var noteNames: [String] {
        model.display == .triad
            ? model.triadTones.sorted { ($0 - model.tonicPC + 12) % 12 < ($1 - model.tonicPC + 12) % 12 }.map(model.name)
            : model.scale.steps.map { model.name(model.tonicPC + $0) }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Picker("Key", selection: $model.key) {
                ForEach(ProtoKey.all) { Text($0.name).tag($0) }
            }
            .help("Key")

            Picker("Show", selection: $model.display) {
                ForEach(ProtoDisplay.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Show a scale or a triad")
        }

        ToolbarItemGroup(placement: .principal) {
            if model.display == .scale {
                Picker("Scale", selection: $model.scale) {
                    ForEach(ProtoScale.allCases) { Text($0.rawValue).tag($0) }
                }
                .help("Scale")
                Picker("Position", selection: $model.positionIndex) {
                    Text("Whole neck").tag(Int?.none)
                    Divider()
                    ForEach(Array(model.positions.enumerated()), id: \.offset) { i, p in
                        Text(p.name).tag(Int?.some(i))
                    }
                }
                .help("Position")
            } else {
                Picker("String set", selection: $model.stringSet) {
                    ForEach(0..<4) { Text(protoStringSets[$0]).tag($0) }
                }
                .help("String set")
                Picker("Inversion", selection: $model.inversion) {
                    ForEach(0..<3) { Text(protoInversions[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Inversion")
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Labels", selection: $model.labelMode) {
                Image(systemName: "textformat").tag(ProtoLabelMode.shown).help("Note names")
                Image(systemName: "textformat.alt").tag(ProtoLabelMode.faded).help("Faded names")
                Image(systemName: "circle.fill").tag(ProtoLabelMode.hidden).help("Dots only")
            }
            .pickerStyle(.segmented)
            .help("Note labels")

            Menu {
                Toggle("Heatmap overlay", isOn: $model.heatmap)
                Button("Shuffle heatmap values") { model.regenerateHeat() }
            } label: {
                Image(systemName: "ladybug")
            }
            .help("Debug")
        }
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            legend(rootColor, "Root")
            legend(toneColor, model.display == .triad ? "Chord tone" : "Scale tone")
            if model.heatmap {
                HStack(spacing: 6) {
                    LinearGradient(colors: [.yellow.opacity(0.3), .orange, .red], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 48, height: 6).clipShape(Capsule())
                    Text("Slower").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu(model.tuning.name) {
                Picker("Tuning", selection: $model.tuning) {
                    ForEach(ProtoTuning.all) { Text($0.name).tag($0) }
                }
                .pickerStyle(.inline)
            }
            .menuStyle(.borderlessButton).fixedSize()
            Menu(model.capo == 0 ? "No capo" : "Capo \(model.capo)") {
                Picker("Capo", selection: $model.capo) {
                    Text("No capo").tag(0)
                    ForEach(1...12, id: \.self) { Text("Capo \($0)").tag($0) }
                }
                .pickerStyle(.inline)
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .font(.callout)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
#endif
