// PROTOTYPE, throwaway: the three variants. See ProtoPhase3.swift.
import SwiftUI
import TheoryCore

private let plan: [(module: String, drills: [(String, String)], seconds: Double)] = [
    ("Notes", [("Note → play it", "2:02"), ("Fret → name it", "2:02")], 245),
    ("Scales", [("Up and down", "5:27")], 327),
    ("Triads", [("Triad → play it", "5:27")], 327),
]

// MARK: P1 — Phase 2's layout kept: neck, target card, strip. Metronome opens as a popover from the status bar.

struct ProtoP1: View {
    @Bindable var m: ProtoModel
    var showsNeck = false
    var body: some View {
        switch m.scene {
        case .setup: setup
        case .summary: summary
        default: playing
        }
    }
    private var playing: some View {
        VStack(spacing: 0) {
            ProtoBlocksBar(); Divider()
            FretboardView(diagram: m.scene == .triad ? m.triadDiagram : m.passDiagram)
                .frame(height: 190).padding(16).sessionCard().padding(.horizontal, 24).padding(.top, 14)
            Spacer(minLength: 8)
            if m.scene == .triad { triad } else { pass }
            Spacer(minLength: 8)
            Divider()
            ProtoKeys(m: m)
        }
        .overlay(alignment: .bottomTrailing) {
            if m.scene == .metronome {
                ProtoMetronomePanel(m: m).background(RoundedRectangle(cornerRadius: 12).fill(.background)).shadow(radius: 12).padding(.trailing, 190).padding(.bottom, 38)
            }
        }
    }
    private var pass: some View {
        VStack(spacing: 10) {
            HStack(spacing: 24) {
                DrillTargetCard(tint: m.scene == .wrong ? .red.opacity(0.12) : Color(nsColor: .controlBackgroundColor)) {
                    if m.scene == .countIn {
                        Text("\(m.beat + 1)").font(.system(size: 76, weight: .bold, design: .rounded))
                        Text("count-in").font(.title2).foregroundStyle(.secondary)
                    } else if m.scene == .metronome {
                        Text("Paused").font(.system(size: 60, weight: .bold, design: .rounded))
                    } else {
                        Text("A major").font(.system(size: 60, weight: .bold, design: .rounded))
                        Text("Up and down · D shape").font(.title2).foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 8) {
                    ProtoBeats(m: m, size: 22)
                    Text("\(m.played) of \(m.route.count)").font(.title3.monospacedDigit())
                    Label(m.stage.rawValue, systemImage: "eye").font(.caption).foregroundStyle(.secondary)
                }.frame(width: 150)
            }
            Label(m.scene == .wrong ? "You played G" : "Last pass: clean · even to ±28 ms · 68 → 72 BPM", systemImage: m.scene == .wrong ? "xmark.circle.fill" : "checkmark.circle")
                .font(.title2.weight(.medium)).foregroundStyle(m.scene == .wrong ? .red : .secondary)
            HStack(spacing: 3) { ForEach(m.route.indices, id: \.self) { i in RoundedRectangle(cornerRadius: 3).fill(i < m.played ? Color.green.opacity(0.6) : i == m.played ? .accentColor : .secondary.opacity(0.15)).frame(width: 18, height: 14) } }
        }
    }
    private var triad: some View {
        VStack(spacing: 10) {
            DrillTargetCard { Text("B minor").font(.system(size: 60, weight: .bold, design: .rounded)); Text("1st inversion · D-G-B").font(.title2).foregroundStyle(.secondary) }
            Label("Listening…", systemImage: "waveform").font(.title2).foregroundStyle(.secondary)
            HStack(spacing: 8) { ForEach(0..<3, id: \.self) { i in
                VStack(spacing: 0) { Text(["4 (D)", "3 (G)", "2 (B)"][i]).font(.caption.weight(.semibold)); Text(i == 0 ? "D" : "–").font(.caption) }
                    .frame(width: 64, height: 38).background(RoundedRectangle(cornerRadius: 6).fill(i == 0 ? .green.opacity(0.2) : i == 1 ? .blue.opacity(0.2) : .gray.opacity(0.1)))
            } }
        }
    }
    private var setup: some View {
        VStack(spacing: showsNeck ? 14 : 20) {
            Text("A major").font(.system(size: showsNeck ? 52 : 64, weight: .bold, design: .rounded))
            HStack { Text("D shape · strings D-G-B").foregroundStyle(.secondary); Button("Reroll") {} }.font(.title3)
            if showsNeck { FretboardView(diagram: { var d = m.passDiagram; d.markers = m.position.locations.map { m.marker($0) }; return d }()).frame(height: 200).padding(.horizontal, 24) }
            Text("− 15 min +").font(.system(size: 44, weight: .semibold, design: .rounded))
            Button { } label: { Text("Start ↩").font(.title).padding(.horizontal, 48).padding(.vertical, 8) }.buttonStyle(.borderedProminent)
            HStack(alignment: .top, spacing: 24) { ForEach(plan, id: \.module) { mod in
                VStack(spacing: 6) { Text(mod.module).font(.headline)
                    HStack { ForEach(mod.drills, id: \.0) { d in VStack { Text(d.0).font(.callout); Text(d.1).foregroundStyle(.secondary) }.frame(width: 130, height: 64).sessionCard() } } }
            } }
            Text("Naturals | All notes      First 12 frets | Whole neck").foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var summary: some View {
        VStack(spacing: 24) {
            Text("15:24").font(.system(size: 84, weight: .bold, design: .rounded))
            HStack(spacing: 16) {
                card("Note → play it", "91%", "1.42 s", "23 prompts · 1 skipped"); card("Fret → name it", "88%", "1.90 s", "25 prompts")
                card("Up and down", "6 of 9", "clean at 76 BPM", "even to ±24 ms"); card("Triad → play it", "82%", "3.1 s a voicing", "38 prompts · 2 skipped")
            }
            Text("Slowest: C♯ on string 5 (A) — 6.2 s").foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func card(_ t: String, _ big: String, _ mid: String, _ small: String) -> some View {
        VStack(spacing: 4) { Text(big).font(.system(size: 36, weight: .bold, design: .rounded)); Text(mid).font(.title3); Text(t); Text(small).font(.caption).foregroundStyle(.secondary) }
            .frame(width: 190, height: 160).sessionCard()
    }
}

// MARK: P2 — no card: one line of text, a tall neck, and the pass as a rising and falling line. Metronome drops down as a strip.

struct ProtoP2: View {
    @Bindable var m: ProtoModel
    var body: some View {
        switch m.scene {
        case .setup: setup
        case .summary: summary
        default:
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(m.scene == .triad ? "B minor · 1st inversion" : "A major · up and down").font(.system(size: 34, weight: .bold, design: .rounded))
                    Spacer()
                    if m.scene == .wrong { Label("You played G", systemImage: "xmark.circle.fill").font(.title2).foregroundStyle(.red) } else if m.scene != .triad { Text("Last: clean · ±28 ms · \(m.stage.rawValue)").foregroundStyle(.secondary) }
                    Spacer()
                    if m.scene != .triad { ProtoBeats(m: m, size: 26) ; Text("\(Int(m.bpm))").font(.title.monospacedDigit().bold()) }
                }.padding(.horizontal, 28).padding(.vertical, 12)
                if m.scene == .metronome { strip }
                FretboardView(diagram: m.scene == .triad ? m.triadDiagram : m.passDiagram).frame(maxHeight: .infinity).padding(.horizontal, 20)
                    .overlay { if m.scene == .countIn { Text("\(m.beat + 1)").font(.system(size: 150, weight: .heavy, design: .rounded)).foregroundStyle(.white).shadow(radius: 8) } }
                if m.scene == .triad {
                    HStack(spacing: 40) { ForEach(0..<3, id: \.self) { i in VStack { Circle().fill(i == 0 ? Color.green : .secondary.opacity(0.15)).overlay { Text(i == 0 ? "D" : "?").font(.title.bold()) }.frame(width: 64); Text(["string 4", "string 3", "string 2"][i]).foregroundStyle(.secondary) } } }.frame(height: 150)
                } else { ProtoContour(m: m).frame(height: 150).padding(.horizontal, 28) }
                ProtoBlocksBar()
                Divider(); ProtoKeys(m: m)
            }
        }
    }
    private var strip: some View {
        HStack(spacing: 18) {
            Slider(value: $m.bpm, in: 40...160).frame(width: 150); Text("\(Int(m.bpm)) BPM").monospacedDigit()
            Toggle("Hold", isOn: $m.hold)
            Picker("", selection: Binding(get: { m.top }, set: { t in m.setSignature(t, t > 5 ? 8 : 4) })) { ForEach(ProtoMetronomePanel.signatures, id: \.0) { Text("\($0.0)/\($0.1)").tag($0.0) } }.frame(width: 80)
            ProtoBeats(m: m, size: 24, editable: true)
            Image(systemName: "speaker.wave.2"); Slider(value: $m.volume).frame(width: 90)
        }.padding(10).frame(maxWidth: .infinity).background(.orange.opacity(0.12))
    }
    private var setup: some View {
        VStack(spacing: 26) {
            HStack(alignment: .firstTextBaseline, spacing: 30) { Text("A major").font(.system(size: 56, weight: .bold, design: .rounded)); Text("D shape · D-G-B").font(.title2).foregroundStyle(.secondary); Button("Reroll") {} }
            FretboardView(diagram: { var d = m.passDiagram; d.markers = m.position.locations.map { m.marker($0) }; return d }()).frame(height: 200).padding(.horizontal, 24)
            GeometryReader { g in HStack(spacing: 4) { ForEach(plan, id: \.module) { mod in
                VStack { Text(mod.module).font(.headline); Text(mod.drills.map { "\($0.0) \($0.1)" }.joined(separator: " · ")).font(.caption) }
                    .frame(width: (g.size.width - 8) * mod.seconds / 899, height: 70).background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.18)))
            } } }.frame(height: 70).padding(.horizontal, 24)
            HStack(spacing: 40) { Text("− 15 min +").font(.title.bold()); Button("Start ↩") {}.buttonStyle(.borderedProminent).controlSize(.large); Text("Naturals · First 12 frets").foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("15:24").font(.system(size: 60, weight: .bold, design: .rounded))
            ForEach([("Notes", "48 prompts · 90% first try · 1.6 s median · 1 skipped"), ("Scales", "9 passes · 6 clean · fastest clean 76 BPM · even to ±24 ms"), ("Triads", "38 prompts · 82% first try · 3.1 s a voicing · 2 skipped")], id: \.0) { r in
                HStack { Text(r.0).font(.title.bold()).frame(width: 140, alignment: .leading); Text(r.1).font(.title3) }
                Divider()
            }
            Text("Slowest: C♯ on string 5 (A) — 6.2 s").foregroundStyle(.secondary)
        }.padding(60).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: P3 — the metronome is always on screen in a rail, and the neck is a close-up of the position.

struct ProtoP3: View {
    @Bindable var m: ProtoModel
    var body: some View {
        switch m.scene {
        case .setup: setup
        case .summary: summary
        default:
            VStack(spacing: 0) {
                ProtoBlocksBar(); Divider()
                HStack(spacing: 0) {
                    if m.scene == .triad { triadRail } else {
                        VStack(spacing: 12) { ProtoBeats(m: m, size: 24); ProtoMetronomePanel(m: m, compact: true) }.padding(.top, 14).frame(width: 270).frame(maxHeight: .infinity, alignment: .top).background(.quaternary.opacity(0.4))
                    }
                    Divider()
                    VStack(spacing: 14) {
                        HStack { Text(title).font(.system(size: 40, weight: .bold, design: .rounded)); Spacer(); if m.scene == .wrong { Text("You played G").font(.title2).foregroundStyle(.red) } else if m.scene != .triad { Text("\(m.played) / \(m.route.count)").font(.title2.monospacedDigit()) } }
                        ProtoCloseUp(m: m).frame(maxHeight: .infinity)
                        Text(m.scene == .triad ? "Listening…" : "Last pass: clean · even to ±28 ms · \(m.stage.rawValue)").foregroundStyle(.secondary)
                    }.padding(24)
                }
                Divider(); ProtoKeys(m: m)
            }
        }
    }
    private var title: String { m.scene == .triad ? "B minor · 1st inversion" : m.scene == .countIn ? "Count-in  \(m.beat + 1)" : m.scene == .metronome ? "Paused" : "A major · up and down" }
    private var triadRail: some View {
        VStack(spacing: 20) { Text("D-G-B").font(.largeTitle.bold()); ForEach([("2 (B)", "–"), ("3 (G)", "–"), ("4 (D)", "D ✓")], id: \.0) { s in HStack { Text(s.0).foregroundStyle(.secondary); Spacer(); Text(s.1).font(.title.bold()) }.padding().sessionCard() } }.padding(20).frame(width: 270)
    }
    private var setup: some View {
        HStack(spacing: 50) {
            VStack(alignment: .leading, spacing: 14) { Text("A major").font(.system(size: 64, weight: .bold, design: .rounded)); Text("D shape\nStrings D-G-B").font(.title2).foregroundStyle(.secondary); Button("Reroll") {}; Text("− 15 min +").font(.system(size: 40, weight: .semibold)); Button { } label: { Text("Start ↩").font(.title).padding(.horizontal, 40) }.buttonStyle(.borderedProminent) }
            VStack(alignment: .leading, spacing: 12) { ForEach(plan, id: \.module) { mod in Text(mod.module).font(.headline); ForEach(mod.drills, id: \.0) { d in HStack { Text(d.0); Spacer(); Text(d.1).foregroundStyle(.secondary) }.padding(.leading, 14) } }; Divider(); Text("Naturals · First 12 frets").foregroundStyle(.secondary) }.frame(width: 340).padding(24).sessionCard()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var summary: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack { Text("15:24").font(.system(size: 70, weight: .bold, design: .rounded)); Text("3 modules · 4 drills").foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 18) {
                Text("Scales").font(.title.bold()); Text("D shape: Shown → Hidden"); Text("72 → 76 BPM, 6 of 9 clean, even to ±24 ms")
                Text("Triads").font(.title.bold()); Text("82% first try, 3.1 s a voicing"); Text("Notes").font(.title.bold()); Text("90% first try, 1.6 s")
            }.font(.title3)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProtoCloseUp: View {
    let m: ProtoModel
    var body: some View {
        Canvas { c, size in
            let d = m.scene == .triad ? m.triadDiagram : m.passDiagram
            let lo = m.scene == .triad ? 1 : max(1, m.position.frets.lowerBound - 1)
            let hi = m.scene == .triad ? 12 : m.position.frets.upperBound + 1
            let w = size.width / CGFloat(hi - lo + 1), h = (size.height - 24) / 6
            c.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: h * 6), cornerRadius: 6), with: .color(FretboardPalette.woodTop))
            for f in lo...hi { let x = CGFloat(f - lo + 1) * w
                c.stroke(Path { $0.move(to: .init(x: x, y: 0)); $0.addLine(to: .init(x: x, y: h * 6)) }, with: .color(FretboardPalette.fretWire), lineWidth: 2)
                c.draw(Text("\(f)").font(.caption), at: .init(x: x - w / 2, y: h * 6 + 12)) }
            for s in 0..<6 { let y = h * (5.5 - CGFloat(s))
                if d.highlightedStrings.contains(s) { c.fill(Path(CGRect(x: 0, y: y - h / 2, width: size.width, height: h)), with: .color(FretboardPalette.stringHighlight)) }
                c.stroke(Path { $0.move(to: .init(x: 0, y: y)); $0.addLine(to: .init(x: size.width, y: y)) }, with: .color(FretboardPalette.woundString), lineWidth: 2.5 - CGFloat(s) * 0.3) }
            for k in d.markers where (lo...hi).contains(k.location.fret) {
                let x = (CGFloat(k.location.fret - lo) + 0.5) * w, y = h * (5.5 - CGFloat(k.location.string)), r = min(w, h) * 0.38
                c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(FretboardPalette.color(for: k.role).opacity(k.isFaint ? 0.28 : 1)))
                if k.isCurrent { c.stroke(Path(ellipseIn: CGRect(x: x - r - 3, y: y - r - 3, width: 2 * r + 6, height: 2 * r + 6)), with: .color(.yellow), lineWidth: 4) }
                if !k.isFaint { c.draw(Text(k.label).font(.title3.bold()).foregroundColor(.white), at: .init(x: x, y: y)) }
            }
        }
    }
}

// MARK: P4 — the mix: P1's setup with the scale on a neck, P2's playing screen zoomed in, P1's metronome panel and summary.

struct ProtoP4: View {
    @Bindable var m: ProtoModel
    var body: some View {
        switch m.scene {
        case .setup, .summary: ProtoP1(m: m, showsNeck: true)
        default:
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 34, weight: .bold, design: .rounded))
                    Spacer()
                    feedback.font(.title2)
                    Spacer()
                    if m.scene != .triad { ProtoBeats(m: m, size: 26); Text("\(Int(m.bpm))").font(.title.monospacedDigit().bold()) }
                }.padding(.horizontal, 28).padding(.vertical, 12)
                ProtoZoomNeck(diagram: m.scene == .triad ? m.triadDiagram : m.passDiagram, frets: frets)
                    .frame(maxHeight: .infinity).padding(.horizontal, 24)
                    .overlay { if m.scene == .countIn { Text("\(m.beat + 1)").font(.system(size: 150, weight: .heavy, design: .rounded)).foregroundStyle(.white).shadow(radius: 8) } }
                if m.scene == .triad {
                    HStack(spacing: 40) { ForEach(0..<3, id: \.self) { i in VStack { Circle().fill(i == 0 ? Color.green : .secondary.opacity(0.15)).overlay { Text(i == 0 ? "D" : "?").font(.title.bold()) }.frame(width: 64); Text(["string 4 (D)", "string 3 (G)", "string 2 (B)"][i]).foregroundStyle(.secondary) } } }.frame(height: 120)
                } else { ProtoContour(m: m).frame(height: 120).padding(.horizontal, 28) }
                ProtoBlocksBar()
                Divider(); ProtoKeys(m: m)
            }
            .overlay(alignment: .bottomTrailing) {
                if m.scene == .metronome {
                    ProtoMetronomePanel(m: m).background(RoundedRectangle(cornerRadius: 12).fill(.background)).shadow(radius: 12).padding(.trailing, 190).padding(.bottom, 38)
                }
            }
        }
    }
    private var title: String { m.scene == .triad ? "B minor · 1st inversion" : m.scene == .metronome ? "Paused" : "A major · up and down" }
    @ViewBuilder private var feedback: some View {
        if m.scene == .wrong { Label("You played G", systemImage: "xmark.circle.fill").foregroundStyle(.red) }
        else if m.scene == .triad { Text("strings D-G-B").foregroundStyle(.secondary) }
        else { Text("Last: clean · ±28 ms · \(m.stage.rawValue)").foregroundStyle(.secondary) }
    }
    /// Scales: two frets either side of the position. Triads: the whole practised range, so that the zoom never gives the voicing away.
    private var frets: ClosedRange<Int> {
        m.scene == .triad ? 0...12 : max(0, m.position.frets.lowerBound - 2)...min(22, m.position.frets.upperBound + 2)
    }
}

/// A section of the neck, with a small whole neck under it showing which.
struct ProtoZoomNeck: View {
    let diagram: FretboardDiagram
    let frets: ClosedRange<Int>
    var body: some View {
        Canvas { c, size in
            let left: CGFloat = 30, hasOpen = frets.lowerBound == 0
            let lo = max(1, frets.lowerBound), hi = frets.upperBound
            let open: CGFloat = hasOpen ? 34 : 0
            let x0 = left + open, w = (size.width - x0) / CGFloat(hi - lo + 1), h = (size.height - 46) / 6
            func cx(_ f: Int) -> CGFloat { f == 0 ? left + open / 2 : x0 + (CGFloat(f - lo) + 0.5) * w }
            func y(_ s: Int) -> CGFloat { h * (5.5 - CGFloat(s)) }
            c.fill(Path(CGRect(x: x0, y: 0, width: size.width - x0, height: h * 6)), with: .linearGradient(Gradient(colors: [FretboardPalette.woodTop, FretboardPalette.woodBottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 6)))
            if hasOpen { c.fill(Path(CGRect(x: x0 - 3, y: 0, width: 6, height: h * 6)), with: .color(FretboardPalette.bone)) }
            for f in lo...hi {
                let x = x0 + CGFloat(f - lo + 1) * w, marked = FretboardGeometry.inlayFrets.contains(f)
                c.stroke(Path { $0.move(to: .init(x: x, y: 0)); $0.addLine(to: .init(x: x, y: h * 6)) }, with: .color(FretboardPalette.fretWire), lineWidth: 2)
                c.draw(Text("\(f)").font(marked ? .callout.bold() : .callout).foregroundColor(.secondary), at: .init(x: cx(f), y: h * 6 + 11))
                if marked { for yy in f == 12 ? [h * 2, h * 4] : [h * 3] { c.fill(Path(ellipseIn: CGRect(x: cx(f) - 5, y: yy - 5, width: 10, height: 10)), with: .color(FretboardPalette.pearl.opacity(0.85))) } }
            }
            for s in 0..<6 {
                if diagram.highlightedStrings.contains(s) { c.fill(Path(CGRect(x: 0, y: y(s) - h * 0.45, width: size.width, height: h * 0.9)), with: .color(FretboardPalette.stringHighlight)) }
                c.stroke(Path { $0.move(to: .init(x: left, y: y(s))); $0.addLine(to: .init(x: size.width, y: y(s))) }, with: .color(s < 3 ? FretboardPalette.woundString : FretboardPalette.plainString), lineWidth: 3 - CGFloat(s) * 0.35)
                c.draw(Text(diagram.stringNames[s]).font(.callout.weight(.medium)).foregroundColor(.secondary), at: .init(x: 12, y: y(s)))
            }
            for k in diagram.markers where k.location.fret == 0 ? hasOpen : (lo...hi).contains(k.location.fret) {
                let r = min(w, h) * 0.4, rect = CGRect(x: cx(k.location.fret) - r, y: y(k.location.string) - r, width: 2 * r, height: 2 * r)
                c.fill(Path(ellipseIn: rect), with: .color(FretboardPalette.color(for: k.role).opacity(k.isFaint ? 0.28 : 1)))
                if k.isCurrent { c.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(.yellow), lineWidth: 4) }
                if !k.isFaint { c.draw(Text(k.label).font(.title3.bold()).foregroundColor(.white), at: .init(x: rect.midX, y: rect.midY)) }
            }
            // Which part of the neck this is.
            let mini = CGRect(x: left, y: size.height - 14, width: size.width - left, height: 8)
            c.fill(Path(roundedRect: mini, cornerRadius: 4), with: .color(.secondary.opacity(0.2)))
            let a = FretboardGeometry(size: CGSize(width: mini.width, height: 200), stringCount: 6, lastFret: 22)
            func frac(_ f: Int) -> CGFloat { (a.wireX(f) - a.wireX(0)) / (a.wireX(22) - a.wireX(0)) }
            let from = mini.minX + mini.width * frac(lo - 1), to = mini.minX + mini.width * frac(hi)
            c.fill(Path(roundedRect: CGRect(x: from, y: mini.minY, width: to - from, height: 8), cornerRadius: 4), with: .color(FretboardPalette.woundString))
        }
    }
}
