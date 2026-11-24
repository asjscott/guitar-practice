// VERDICT (23 Nov 2026): P4. P1's setup plus the theme's scale on a neck; P2's playing screen with P3's zoom; P1's metronome panel and summary.
// PROTOTYPE, throwaway. Three variants of the Phase 3 screens (P1, P2, P3) on one Prototype screen.
// ← → variant · 1–7 scene · F fade stage · Space plays or stops the fake pass · M metronome scene. No audio, nothing saved.
import Observation
import SwiftUI
import TheoryCore

enum ProtoVariant: String, CaseIterable { case p1 = "P1", p2 = "P2", p3 = "P3", p4 = "P4"
    var title: String { switch self { case .p1: "Card (as Phase 2)"; case .p2: "Wide neck + contour"; case .p3: "Metronome rail + close-up"; case .p4: "Mix: P1 + P2, zoomed" } }
}
enum ProtoScene: String, CaseIterable { case setup, countIn, pass, wrong, triad, metronome, summary }
enum ProtoStage: String, CaseIterable { case shown = "Shown", faded = "Faded", hidden = "Hidden" }

@MainActor @Observable final class ProtoModel {
    var variant = ProtoVariant.p1
    var scene = ProtoScene.pass
    var stage = ProtoStage.shown
    var step = 9
    var playing = false
    var hold = false
    var sound = true
    var bpm = 72.0
    var top = 4
    var bottom = 4
    var volume = 0.7
    var emphasis: Set<Int> = [0]
    let fretboard = Fretboard(tuning: .standard)
    let scale = Key.major(.a).scale
    let position: Position
    let route: [FretboardLocation]

    init(scene: ProtoScene = .pass, variant: ProtoVariant = .p1, stage: ProtoStage = .shown) {
        self.scene = scene; self.variant = variant; self.stage = stage
        position = fretboard.cagedPositions(of: scale).first { $0.cagedShape == .d && $0.octave == 0 }
            ?? fretboard.cagedPositions(of: scale)[0]
        let fb = fretboard, root = scale.tonic.pitchClass
        let up = position.locations.sorted { fb.pitch(at: $0) < fb.pitch(at: $1) }
        let first = up.firstIndex { fb.pitch(at: $0).pitchClass == root } ?? 0
        route = Array(up[first...]) + Array(up.reversed().dropFirst()) + Array(up[1...max(1, first)])
    }
    var current: FretboardLocation { route[min(step, route.count - 1)] }
    /// The last note played: the next one is never lit.
    var played: Int { scene == .countIn ? 0 : step }
    var last: FretboardLocation? { played > 0 ? route[min(played, route.count) - 1] : nil }
    var beat: Int { step % top }
    func isRoot(_ l: FretboardLocation) -> Bool { fretboard.pitch(at: l).pitchClass == scale.tonic.pitchClass }
    func name(_ l: FretboardLocation) -> String { fretboard.name(at: l, in: scale).description }
    func marker(_ l: FretboardLocation, faint: Bool = false) -> FretboardDiagram.Marker {
        .init(location: l, label: name(l), role: isRoot(l) ? .root : .tone, isFaint: faint)
    }
    var passDiagram: FretboardDiagram {
        var d = FretboardDiagram(stringNames: fretboard.stringNames(in: nil).map(\.description))
        let base: [FretboardDiagram.Marker] = switch stage {
        case .shown: position.locations.map { marker($0, faint: false) }
        case .faded: position.locations.map { marker($0, faint: true) }
        case .hidden: position.locations.filter(isRoot).map { marker($0, faint: true) }
        }
        d.markers = base.filter { $0.location != last } + (scene == .countIn ? [] : last.map { l in var k = marker(l); k.isCurrent = true; return [k] } ?? [])
        return d
    }
    /// A minor, 1st inversion, D-G-B; one note in.
    var triadVoicing: TriadVoicing? {
        fretboard.voicings(of: Triad(.minor, root: .b), inversion: .first, on: .dGB).first
    }
    var triadDiagram: FretboardDiagram {
        var d = FretboardDiagram(stringNames: fretboard.stringNames(in: nil).map(\.description))
        d.highlightedStrings = Array(StringSet.dGB.strings)
        if let l = triadVoicing?.locations.first { d.markers = [.init(location: l, label: fretboard.name(at: l, in: scale).description, role: .tone)] }
        return d
    }
    func toggle(_ beat: Int) { if emphasis.contains(beat) { emphasis.remove(beat) } else { emphasis.insert(beat) } }
    func setSignature(_ t: Int, _ b: Int) {
        top = t; bottom = b
        emphasis = b == 8 && t % 3 == 0 ? Set(stride(from: 0, to: t, by: 3)) : [0]
    }
    func run() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60 / bpm))
            if playing { step = step + 1 > route.count ? 0 : step + 1 }
        }
    }
}

struct ProtoScreen: View {
    @State var model: ProtoModel
    var showsSwitcher = true
    var body: some View {
        Group {
            switch model.variant {
            case .p1: ProtoP1(m: model)
            case .p2: ProtoP2(m: model)
            case .p3: ProtoP3(m: model)
            case .p4: ProtoP4(m: model)
            }
        }
        .overlay(alignment: .bottom) { if showsSwitcher { switcher.padding(.bottom, 40) } }
        .task { await model.run() }
        .onPlainKey { key in
            switch key {
            case .space: model.playing.toggle(); return true
            case .character("\u{f702}"): cycle(-1); return true
            case .character("\u{f703}"): cycle(1); return true
            case .character("f"):
                let all = ProtoStage.allCases
                model.stage = all[(all.firstIndex(of: model.stage)! + 1) % all.count]; return true
            case .character("m"): model.scene = model.scene == .metronome ? .pass : .metronome; return true
            case .character(let c):
                guard let n = Int(c), ProtoScene.allCases.indices.contains(n - 1) else { return false }
                model.scene = ProtoScene.allCases[n - 1]; return true
            default: return false
            }
        }
    }
    private func cycle(_ by: Int) {
        let all = ProtoVariant.allCases
        model.variant = all[(all.firstIndex(of: model.variant)! + by + all.count) % all.count]
    }
    private var switcher: some View {
        HStack(spacing: 10) {
            Button("←") { cycle(-1) }
            Text("\(model.variant.rawValue) · \(model.variant.title)").frame(width: 190)
            Button("→") { cycle(1) }
            Picker("", selection: $model.scene) { ForEach(Array(ProtoScene.allCases.enumerated()), id: \.element) { Text("\($0.offset + 1) \($0.element.rawValue)").tag($0.element) } }.frame(width: 130)
            Picker("", selection: $model.stage) { ForEach(ProtoStage.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 100)
            Button(model.playing ? "Stop" : "Play") { model.playing.toggle() }
        }
        .buttonStyle(.plain).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 8)
        .background(Capsule().fill(.purple)).shadow(radius: 6).environment(\.colorScheme, .dark)
    }
}

// MARK: - Shared bits (data only; each variant has its own layout)

struct ProtoBeats: View {
    let m: ProtoModel
    var size: CGFloat = 18
    var editable = false
    var body: some View {
        HStack(spacing: size * 0.45) {
            ForEach(0..<m.top, id: \.self) { i in
                let strong = m.emphasis.contains(i), now = i == m.beat && m.scene != .setup
                Button { if editable { m.toggle(i) } } label: {
                    ZStack {
                        Circle().fill(now && !editable ? Color.orange : strong ? Color.accentColor : Color.secondary.opacity(0.25))
                        if editable { Text("\(i + 1)").font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(strong ? .white : .secondary) }
                    }
                    .frame(width: strong ? size : size * (editable ? 0.85 : 0.6), height: size)
                }.buttonStyle(.plain)
            }
        }
    }
}

struct ProtoMetronomePanel: View {
    @Bindable var m: ProtoModel
    var compact = false
    static let signatures = [(2, 4), (3, 4), (4, 4), (5, 4), (6, 8), (7, 8), (9, 8), (12, 8)]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button { m.bpm = max(40, m.bpm - 4) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).font(.title)
                Text("\(Int(m.bpm))").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit().frame(width: 92)
                Button { m.bpm = min(160, m.bpm + 4) } label: { Image(systemName: "plus.circle") }.buttonStyle(.plain).font(.title)
                Text("BPM").foregroundStyle(.secondary)
            }
            Slider(value: $m.bpm, in: 40...160)
            Toggle("Hold tempo (no ladder)", isOn: $m.hold)
            Divider()
            Text("Time signature").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                ForEach(Self.signatures, id: \.0) { s in
                    let on = m.top == s.0 && m.bottom == s.1
                    Button("\(s.0)/\(s.1)") { m.setSignature(s.0, s.1) }.buttonStyle(.plain)
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.accentColor : .secondary.opacity(0.12)))
                        .foregroundStyle(on ? .white : .primary)
                }
            }
            Text("Emphasise beats (click to change)").font(.caption).foregroundStyle(.secondary)
            ProtoBeats(m: m, size: m.top > 7 ? 18 : 26, editable: true)
            Divider()
            HStack { Image(systemName: "speaker.wave.2"); Slider(value: $m.volume); Toggle("Sound", isOn: $m.sound) }
        }
        .padding(16).frame(width: compact ? 250 : 320)
    }
}

struct ProtoChip: View {
    let m: ProtoModel
    var body: some View {
        Button { m.scene = m.scene == .metronome ? .pass : .metronome } label: {
            Label("\(m.bottom == 8 ? "♪" : "♩") = \(Int(m.bpm)) · \(m.top)/\(m.bottom)", systemImage: "metronome")
                .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(.secondary.opacity(0.15)))
        }.buttonStyle(.plain)
    }
}

struct ProtoKeys: View {
    let m: ProtoModel
    var body: some View {
        HStack(spacing: 12) {
            ForEach(["Space next", "S skip", "R restart", "H hint", "[ ] tempo", "M metronome", "P pause", "Esc end"], id: \.self) { Text($0) }
            Spacer()
            if m.scene != .triad { ProtoChip(m: m) }
            Text("A major · D shape · D-G-B")
        }.sessionStatusBar()
    }
}

struct ProtoBlocksBar: View {
    let items = [("Note → play it", 1.0), ("Fret → name it", 1.0), ("Up and down", 0.4), ("Triad → play it", 0.0)]
    var body: some View {
        HStack(spacing: 12) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(item.0); Spacer(); Text(item.1 == 1 ? "2:02" : "5:27") }.font(.caption.weight(item.1 == 0.4 ? .semibold : .regular))
                    ProgressView(value: item.1)
                }
            }
            Text("Ends 18:42").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 24).padding(.vertical, 10)
    }
}

/// The pass as a line that rises and falls; played notes fill in, the rest are outlines.
struct ProtoContour: View {
    let m: ProtoModel
    var body: some View {
        Canvas { c, size in
            let ps = m.route.map { m.fretboard.pitch(at: $0).midi }, lo = ps.min()!, hi = ps.max()!
            for (i, p) in ps.enumerated() {
                let x = 12 + (size.width - 24) * CGFloat(i) / CGFloat(ps.count - 1)
                let y = 12 + (size.height - 24) * (1 - CGFloat(p - lo) / CGFloat(hi - lo))
                let r = CGRect(x: x - 7, y: y - 7, width: 14, height: 14)
                let root = m.isRoot(m.route[i])
                if i < m.played { c.fill(Path(ellipseIn: r), with: .color(root ? FretboardPalette.root : FretboardPalette.tone)) }
                else { c.stroke(Path(ellipseIn: r), with: .color(.secondary.opacity(i == m.played ? 0.9 : 0.3)), lineWidth: i == m.played ? 2.5 : 1) }
            }
        }
    }
}
