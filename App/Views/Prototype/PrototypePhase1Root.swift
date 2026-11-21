// PROTOTYPE — throwaway.
// Plan: the Phase 1 main window — a sidebar (Explorer · Tuner · Drill) — with three structurally
// different Tuner layouts (T1–T3) and three Note → play it drill layouts (D1–D3), switched with the
// floating bar (or ← / →). The bar also fakes the guitar: pluck a string, detune, play the right or
// a wrong note. No audio, no detector. DEBUG builds only.

import SwiftUI
import TheoryCore

#if DEBUG
struct PrototypePhase1Root: View {
    enum Screen: String, CaseIterable, Identifiable {
        case explorer = "Explorer", tuner = "Tuner", drill = "Drill"
        var id: Self { self }
        var icon: String {
            switch self {
            case .explorer: "guitars"
            case .tuner: "tuningfork"
            case .drill: "target"
            }
        }
    }

    @SceneStorage("proto.screen") private var screen: Screen = .tuner
    @AppStorage("proto.tunerVariant") private var tunerVariant = "T1"
    @AppStorage("proto.drillVariant") private var drillVariant = "D1"
    @State private var listen = ProtoListen()
    @State private var explorer = ExplorerViewModel()

    static let tunerVariants: [(key: String, name: String)] = [("T1", "Needle"), ("T2", "Six strings"), ("T3", "On the neck")]
    static let drillVariants: [(key: String, name: String)] = [("D1", "Prompt over neck"), ("D2", "Flashcard"), ("D3", "Neck + inspector")]

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<Screen?>(get: { screen }, set: { if let s = $0 { screen = s } })) {
                Section("Practice") {
                    ForEach(Screen.allCases) { s in
                        Label(s.rawValue, systemImage: s.icon).tag(s)
                    }
                }
                Section("Later") {
                    Label("Session", systemImage: "play.circle").foregroundStyle(.tertiary)
                    Label("Dashboard", systemImage: "chart.bar").foregroundStyle(.tertiary)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            ZStack(alignment: .bottom) {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, screen == .explorer ? 0 : 56)
                if screen != .explorer {
                    ProtoBar(screen: screen, listen: listen, tunerVariant: $tunerVariant, drillVariant: $drillVariant)
                        .padding(.bottom, 10)
                }
            }
        }
        .frame(minWidth: 1100, minHeight: 600)
        .onChange(of: screen) { if screen != .drill { listen.stop() } }
        .onAppear { ProtoSnapshots.runIfRequested() }
    }

    @ViewBuilder private var detail: some View {
        switch screen {
        case .explorer:
            ExplorerView(model: explorer)
        case .tuner:
            Group {
                switch tunerVariant {
                case "T2": TunerT2(listen: listen)
                case "T3": TunerT3(listen: listen)
                default: TunerT1(listen: listen)
                }
            }
            .navigationTitle("Tuner")
            .navigationSubtitle("Standard tuning · A4 = 440 Hz")
        case .drill:
            Group {
                switch drillVariant {
                case "D2": DrillD2(listen: listen)
                case "D3": DrillD3(listen: listen)
                default: DrillD1(listen: listen)
                }
            }
            .navigationTitle("Note → play it")
            .navigationSubtitle("Standard tuning")
        }
    }
}

// MARK: - Floating bar: variant switcher + fake guitar

private struct ProtoBar: View {
    let screen: PrototypePhase1Root.Screen
    @Bindable var listen: ProtoListen
    @Binding var tunerVariant: String
    @Binding var drillVariant: String

    private var variants: [(key: String, name: String)] {
        screen == .tuner ? PrototypePhase1Root.tunerVariants : PrototypePhase1Root.drillVariants
    }
    private var current: Binding<String> { screen == .tuner ? $tunerVariant : $drillVariant }
    private var index: Int { variants.firstIndex { $0.key == current.wrappedValue } ?? 0 }

    var body: some View {
        HStack(spacing: 12) {
            Button { current.wrappedValue = variants[(index + variants.count - 1) % variants.count].key } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Text("\(variants[index].key) (\(variants[index].name))").font(.callout.bold()).frame(minWidth: 160)
            Button { current.wrappedValue = variants[(index + 1) % variants.count].key } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Divider().frame(height: 16)
            Text("🎸").font(.callout)
            if screen == .tuner { tunerControls } else { drillControls }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Capsule().fill(.black.opacity(0.85)))
        .shadow(radius: 6)
    }

    private var tunerControls: some View {
        HStack(spacing: 8) {
            ForEach(listen.tuning.strings, id: \.self) { s in
                Button("\(listen.tuning.stringNumber(ofString: s))") { listen.pluckString(s) }
                    .font(.caption.monospaced())
            }
            Slider(value: Binding(get: { listen.tunerCents }, set: { listen.tunerMidi = Double(listen.tunerNearest) + $0 / 100 }), in: -49...49)
                .frame(width: 120)
            Button(listen.signal ? "mute" : "unmute") { listen.signal.toggle() }.font(.caption)
            Text(String(format: "%@%d %+.0f¢", listen.tunerNoteName, listen.tunerOctave, listen.tunerCents))
                .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.75)).frame(width: 80, alignment: .leading)
        }
    }

    private var drillControls: some View {
        HStack(spacing: 10) {
            Button("right note (C)") { listen.playCorrect() }.keyboardShortcut("c", modifiers: [])
            Button("wrong note (W)") { listen.playWrong() }.keyboardShortcut("w", modifiers: [])
            Button("time out") { listen.timeOut() }
            Divider().frame(height: 16)
            Text(listen.stateLine).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
        }
        .font(.caption)
    }
}

// MARK: - Shared prototype bits

/// A translucent band across one string of a `FretboardView`, laid over it.
struct ProtoStringBand: View {
    let string: Int
    let stringCount: Int
    var color: Color = .yellow

    var body: some View {
        GeometryReader { geo in
            let g = FretboardGeometry(size: geo.size, stringCount: stringCount, lastFret: Fretboard.frets.upperBound)
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.22))
                .frame(width: g.neck.maxX, height: g.rowHeight * 0.9)
                .position(x: g.neck.maxX / 2, y: g.y(ofString: string))
        }
        .allowsHitTesting(false)
    }
}

/// Input level meter (fake level, green → amber → red).
struct ProtoMeter: View {
    let level: Double
    var vertical = false

    var body: some View {
        GeometryReader { geo in
            let length = vertical ? geo.size.height : geo.size.width
            ZStack(alignment: vertical ? .bottom : .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(LinearGradient(colors: [.green, .green, .yellow, .red], startPoint: vertical ? .bottom : .leading, endPoint: vertical ? .top : .trailing))
                    .frame(width: vertical ? nil : length * level, height: vertical ? length * level : nil)
            }
        }
        .frame(width: vertical ? 6 : nil, height: vertical ? nil : 6)
        .help("Input 1 · Scarlett 2i2 (fake)")
    }
}

/// The input line shown on listening screens.
struct ProtoInputLabel: View {
    let level: Double
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill").foregroundStyle(.secondary)
            Text("Scarlett 2i2 · Input 1").foregroundStyle(.secondary)
            ProtoMeter(level: level).frame(width: 80)
        }
        .font(.caption)
    }
}

func protoCentsColor(_ cents: Double) -> Color {
    abs(cents) <= 5 ? .green : abs(cents) <= 20 ? .yellow : .orange
}
#endif
