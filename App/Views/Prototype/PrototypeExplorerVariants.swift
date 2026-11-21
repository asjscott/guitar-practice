// PROTOTYPE — throwaway.
// Plan: three structurally different layouts of the Phase 0 fretboard explorer, on the app's
// main window, switched with the floating bar at the bottom (or ← / →). Launch a given one with
// the scheme argument `-protoVariant B`. DEBUG builds only.

import SwiftUI

#if DEBUG
struct PrototypeExplorerRoot: View {
    @AppStorage("protoVariant2") private var variant = "A2"
    @State private var model = PrototypeExplorerModel()
    private let variants: [(key: String, name: String)] = [
        ("A", "Control strip"), ("A2", "Control strip, refined"), ("B", "Inspector sidebar"), ("C", "Neck-first"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch variant {
                case "A2": VariantA2(model: model)
                case "B": VariantB(model: model)
                case "C": VariantC(model: model)
                default: VariantA(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 56)

            switcher.padding(.bottom, 10)
        }
        .frame(minWidth: 900, minHeight: 520)
        .onAppear { model.regenerateHeat() }
    }

    private var index: Int { variants.firstIndex { $0.key == variant } ?? 0 }

    private var switcher: some View {
        HStack(spacing: 12) {
            Button { variant = variants[(index + variants.count - 1) % variants.count].key } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Text("\(variants[index].key) (\(variants[index].name))").font(.callout.bold()).frame(minWidth: 170)
            Button { variant = variants[(index + 1) % variants.count].key } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Divider().frame(height: 16)
            Text(stateLine).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.75))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Capsule().fill(.black.opacity(0.85)))
        .shadow(radius: 6)
    }

    private var stateLine: String {
        let pos = model.display == .triad
            ? "\(protoStringSets[model.stringSet]) \(protoInversions[model.inversion]) · \(model.triadVoicings.count) voicings"
            : (model.positionIndex.flatMap { model.positions.indices.contains($0) ? model.positions[$0].name : nil } ?? "whole neck")
        return "\(model.keyTitle) \(model.scale.rawValue) · \(pos) · \(model.tuning.name) · capo \(model.capo) · labels \(model.labelMode.rawValue.lowercased())\(model.heatmap ? " · heat" : "")"
    }
}

// MARK: - Shared little controls (prototype-only)

private struct PositionPicker: View {
    @Bindable var model: PrototypeExplorerModel
    var body: some View {
        Picker("Position", selection: $model.positionIndex) {
            Text("Whole neck").tag(Int?.none)
            ForEach(Array(model.positions.enumerated()), id: \.offset) { i, p in
                Text(p.name).tag(Int?.some(i))
            }
        }
    }
}

// MARK: - A: Control strip — fretboard on top, one dense row of controls below

private struct VariantA: View {
    @Bindable var model: PrototypeExplorerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PrototypeFretboard(model: model).frame(height: 240)
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Picker("Key", selection: $model.key) { ForEach(ProtoKey.all) { Text($0.name).tag($0) } }.frame(width: 110)
                Picker("", selection: $model.display) { ForEach(ProtoDisplay.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 140)
                if model.display == .scale {
                    Picker("Scale", selection: $model.scale) { ForEach(ProtoScale.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 210)
                    PositionPicker(model: model).frame(width: 190)
                } else {
                    Picker("Strings", selection: $model.stringSet) { ForEach(0..<4) { Text(protoStringSets[$0]).tag($0) } }.frame(width: 150)
                    Picker("", selection: $model.inversion) { ForEach(0..<3) { Text(protoInversions[$0]).tag($0) } }
                        .pickerStyle(.segmented).frame(width: 150)
                }
            }
            HStack(spacing: 18) {
                Picker("Labels", selection: $model.labelMode) { ForEach(ProtoLabelMode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 240)
                Picker("Tuning", selection: $model.tuning) { ForEach(ProtoTuning.all) { Text($0.name).tag($0) } }.frame(width: 190)
                Stepper("Capo \(model.capo)", value: $model.capo, in: 0...12)
                Toggle("Heatmap (debug)", isOn: $model.heatmap)
                Spacer()
            }
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
    }
}


// MARK: - B: Inspector sidebar — all choices in a scrolling sidebar, fretboard alone in the detail

private struct VariantB: View {
    @Bindable var model: PrototypeExplorerModel
    var body: some View {
        HStack(spacing: 0) {
            List {
                Section("Key") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(38)), count: 6), spacing: 6) {
                        ForEach(ProtoKey.all) { k in
                            Button(k.name) { model.key = k }
                                .buttonStyle(.bordered)
                                .tint(model.key == k ? .accentColor : .gray)
                        }
                    }
                }
                Section("Show") {
                    Picker("", selection: $model.display) { ForEach(ProtoDisplay.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden()
                }
                if model.display == .scale {
                    Section("Scale") {
                        Picker("", selection: $model.scale) { ForEach(ProtoScale.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.radioGroup).labelsHidden()
                    }
                    Section("Position (\(model.effectiveSystem.rawValue))") {
                        positionRow(nil, title: "Whole neck", detail: "")
                        ForEach(Array(model.positions.enumerated()), id: \.offset) { i, p in
                            positionRow(i, title: p.name, detail: "frets \(p.minFret)–\(p.maxFret)")
                        }
                    }
                } else {
                    Section("Triad") {
                        Picker("String set", selection: $model.stringSet) { ForEach(0..<4) { Text(protoStringSets[$0]).tag($0) } }
                        Picker("Inversion", selection: $model.inversion) { ForEach(0..<3) { Text(protoInversions[$0]).tag($0) } }
                    }
                }
                Section("Display") {
                    Picker("Labels", selection: $model.labelMode) { ForEach(ProtoLabelMode.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("Heatmap (debug)", isOn: $model.heatmap)
                }
                Section("Instrument (lives in Settings)") {
                    Picker("Tuning", selection: $model.tuning) { ForEach(ProtoTuning.all) { Text($0.name).tag($0) } }
                    Stepper("Capo \(model.capo)", value: $model.capo, in: 0...12)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 270)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("\(model.keyTitle) \(model.scale.rawValue.lowercased())").font(.title2.bold())
                PrototypeFretboard(model: model).frame(height: 260)
                Spacer()
            }
            .padding(20)
        }
    }

    private func positionRow(_ i: Int?, title: String, detail: String) -> some View {
        Button { model.positionIndex = i } label: {
            HStack {
                Image(systemName: model.positionIndex == i ? "largecircle.fill.circle" : "circle")
                Text(title)
                Spacer()
                Text(detail).foregroundStyle(.secondary).font(.caption)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - C: Neck-first — huge neck, keys as a row of 12, positions picked from brackets on the neck

private struct VariantC: View {
    @Bindable var model: PrototypeExplorerModel
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(model.keyTitle).font(.system(size: 34, weight: .bold))
                Menu(model.display == .scale ? model.scale.rawValue : "Triad · \(protoStringSets[model.stringSet]) · \(protoInversions[model.inversion])") {
                    ForEach(ProtoScale.allCases) { s in Button(s.rawValue) { model.display = .scale; model.scale = s } }
                    Divider()
                    ForEach(0..<4) { ss in
                        Menu("Triad on \(protoStringSets[ss])") {
                            ForEach(0..<3) { inv in Button("\(protoInversions[inv]) inversion") { model.display = .triad; model.stringSet = ss; model.inversion = inv } }
                        }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize().font(.title3)
                Spacer()
                Menu {
                    Picker("Labels", selection: $model.labelMode) { ForEach(ProtoLabelMode.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("Heatmap (debug)", isOn: $model.heatmap)
                    Picker("Tuning", selection: $model.tuning) { ForEach(ProtoTuning.all) { Text($0.name).tag($0) } }
                    Picker("Capo", selection: $model.capo) { ForEach(0...12, id: \.self) { Text("Capo \($0)").tag($0) } }
                } label: { Image(systemName: "slider.horizontal.3") }
                .menuStyle(.borderlessButton).fixedSize()
            }

            HStack(spacing: 6) {
                ForEach(ProtoKey.all) { k in
                    Text(k.name)
                        .font(.headline)
                        .frame(width: 44, height: 30)
                        .background(RoundedRectangle(cornerRadius: 6).fill(model.key == k ? Color.accentColor : Color.gray.opacity(0.15)))
                        .foregroundStyle(model.key == k ? .white : .primary)
                        .onTapGesture { model.key = k }
                }
                Spacer()
            }

            if model.display == .scale { positionBrackets.frame(height: 26) }
            PrototypeFretboard(model: model).frame(maxHeight: .infinity)
        }
        .padding(20)
    }

    // Brackets aligned to the real-neck fret spacing; click one to pick that position.
    private var positionBrackets: some View {
        GeometryReader { geo in
            let openW: CGFloat = 34, neckW = geo.size.width - openW - 8
            let full = 1 - pow(2, -22.0 / 12)
            let wx: (Int) -> CGFloat = { n in openW + neckW * CGFloat((1 - pow(2, -Double(max(n, 0)) / 12)) / full) }
            ZStack(alignment: .topLeading) {
                ForEach(Array(model.positions.enumerated()), id: \.offset) { i, p in
                    let x0 = p.minFret == 0 ? 0 : wx(p.minFret - 1), x1 = wx(p.maxFret)
                    let selected = model.positionIndex == i
                    Text(p.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .frame(width: max(x1 - x0 - 2, 20), height: 22)
                        .background(Capsule().fill(selected ? Color.accentColor : Color.gray.opacity(0.2)))
                        .foregroundStyle(selected ? .white : .primary)
                        .offset(x: x0, y: i % 2 == 0 ? 0 : 0)
                        .onTapGesture { model.positionIndex = selected ? nil : i }
                }
            }
        }
    }
}
#endif
