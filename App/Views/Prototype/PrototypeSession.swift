// PROTOTYPE — throwaway, DEBUG only. No audio, planner, persistence or real scoring.
// Question: what should the Phase 2 session (setup, Ready card, player, pause, summary) and the new drills look like?
// Plan: three structurally different session flows on the new Session screen, switched with the floating bar (← / →):
// S1 Stage (D4 plus a block bar), S2 Focus (one big thing at a time), S3 Agenda (a rail that persists throughout).

import Observation
import SwiftUI
import TheoryCore

#if DEBUG
enum ProtoDrill: String, CaseIterable, Identifiable {
    case fretName = "Fret → name it", play = "Note → play it", all = "All instances", hear = "Hear → find it"
    var id: Self { self }
    var icon: String {
        switch self {
        case .fretName: "keyboard"
        case .play: "target"
        case .all: "square.grid.3x3"
        case .hear: "ear"
        }
    }
    var how: String {
        switch self {
        case .fretName: "A fret lights up. Type its name, then Return."
        case .play: "Play the note on the string shown."
        case .all: "Find every one, string 6 to string 1, lowest fret first."
        case .hear: "Hear the open string, then a note. Find that note."
        }
    }
    var usesKeyboard: Bool { self == .fretName }
}

enum ProtoStage: String, CaseIterable { case setup = "Setup", ready = "Ready", playing = "Playing", paused = "Paused", summary = "Summary" }
enum ProtoResult: String, CaseIterable { case waiting = "Waiting", wrong = "Wrong", right = "Right", timeout = "Timeout" }

@Observable @MainActor
final class ProtoSession {
    var stage: ProtoStage = .setup
    var result: ProtoResult = .waiting
    var minutes = 30.0
    var naturals = false
    var firstFrets = true
    var index = 0
    var typed = ""
    var foundCount = 4
    var readyLeft = 5.0
    var elapsedInBlock = 170.0
    var extra: [Int: Double] = [:]
    let fretboard = Fretboard(tuning: .standard)

    var blocks: [ProtoDrill] { minutes < 12 ? Array(ProtoDrill.allCases.prefix(3)) : ProtoDrill.allCases }
    var drill: ProtoDrill { blocks[min(index, blocks.count - 1)] }
    var baseSeconds: Double { minutes * 60 / Double(blocks.count) }
    func length(_ i: Int) -> Double { baseSeconds + (extra[i] ?? 0) }
    var left: Double { length(index) - elapsedInBlock }
    var fraction: Double { min(1, max(0, elapsedInBlock / length(index))) }
    var overtime: Bool { left < 0 }
    var timeText: String { (overtime ? "+" : "") + Self.clock(abs(left)) }
    static func clock(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
    var nextName: String { index + 1 < blocks.count ? blocks[index + 1].rawValue : "Summary" }
    var finish: String {
        let after = (index + 1 < blocks.count) ? (index + 1..<blocks.count).map { length($0) }.reduce(0, +) : 0
        return Date.now.addingTimeInterval(max(0, left) + after).formatted(date: .omitted, time: .shortened)
    }

    // One fixed, realistic prompt per drill: theme B♭ major.
    var target: FretboardLocation {
        switch drill {
        case .fretName: .init(string: 1, fret: 8)      // F on string 5
        case .play: .init(string: 3, fret: 3)          // B♭ on string 3
        case .all: sweep[min(foundCount, sweep.count - 1)]
        case .hear: .init(string: 4, fret: 4)          // E♭ on string 2
        }
    }
    var name: String {
        switch drill {
        case .fretName: "F"
        case .play: "B♭"
        case .all: "C"
        case .hear: "E♭"
        }
    }
    var sweep: [FretboardLocation] {
        let c = Pitch(60).pitchClass
        return fretboard.strings.flatMap { fretboard.locations(of: c, onString: $0, frets: 0...12) }
    }
    var stringLabel: String { fretboard.tuning.stringLabel(ofString: target.string) }

    /// The big line and the line under it.
    var headline: String {
        switch drill {
        case .fretName: typed.isEmpty ? "?" : typed
        case .play: name
        case .all: "every C"
        case .hear: result == .right || result == .timeout ? name : "♪"
        }
    }
    var subline: String {
        switch drill {
        case .fretName: "\(stringLabel), fret \(target.fret)"
        case .play: "on \(stringLabel)"
        case .all: "next: \(stringLabel) · \(foundCount + (result == .right ? 1 : 0)) of \(sweep.count)"
        case .hear: "on \(stringLabel)"
        }
    }
    var feedback: (text: String, icon: String, color: Color) {
        switch result {
        case .waiting:
            drill == .fretName ? ("Type A–G, then # or b", "keyboard", .secondary) : ("Listening…", "waveform", .secondary)
        case .wrong:
            (drill == .hear ? "Too low" : drill == .fretName ? "Not G" : "You played G", "xmark.circle.fill", .red)
        case .right: ("\(name) · fret \(target.fret) · 1.12 s", "checkmark.circle.fill", .green)
        case .timeout: ("Time's up: \(name), fret \(target.fret)", "clock.badge.exclamationmark", .orange)
        }
    }
    var tint: Color {
        switch result {
        case .waiting: Color(nsColor: .controlBackgroundColor)
        case .wrong: .red.opacity(0.12)
        case .right: .green.opacity(0.15)
        case .timeout: .orange.opacity(0.15)
        }
    }
    var diagram: FretboardDiagram {
        var d = FretboardDiagram(stringNames: fretboard.stringNames(in: nil).map(\.description))
        guard stage == .playing else { return d }
        let revealed = result == .right || result == .timeout
        d.highlightedString = drill == .fretName ? nil : target.string
        switch drill {
        case .fretName:
            d.markers = [.init(location: target, label: revealed ? name : "?", role: .root)]
        case .all:
            d.markers = sweep.prefix(foundCount).map { .init(location: $0, label: "C", role: .tone) }
            if revealed { d.markers.append(.init(location: target, label: "C", role: .root)) }
        default:
            if revealed { d.markers = [.init(location: target, label: name, role: .root)] }
        }
        return d
    }

    // MARK: Actions

    func start() { index = 0; extra = [:]; ready() }
    func ready() { stage = .ready; readyLeft = 5; elapsedInBlock = 0; result = .waiting; typed = "" }
    func space() {
        switch stage {
        case .ready: stage = .playing
        case .playing: if index + 1 < blocks.count { index += 1; ready() } else { stage = .summary }
        default: break
        }
    }
    func pause() { if stage == .playing { stage = .paused } else if stage == .paused { stage = .playing; result = .waiting } }
    func skip() { if stage == .playing { if drill == .all { foundCount = (foundCount + 1) % sweep.count }; result = .waiting; typed = "" } }
    func repeatIt() { if drill == .all { foundCount = 0 }; result = .waiting }
    func extend() { if stage == .playing { extra[index, default: 0] += 120 } }
    func type(_ s: String) {
        guard stage == .playing, drill == .fretName else { return }
        if s == "b", !typed.isEmpty { typed += "♭" } else if s == "#" { if !typed.isEmpty { typed += "♯" } } else { typed = s.uppercased() }
    }
    func enter() {
        if stage == .setup { start() } else if stage == .summary { stage = .setup }
        else if stage == .playing, drill == .fretName { result = typed == name ? .right : .wrong }
    }
    func tick(_ dt: Double) {
        if stage == .playing { elapsedInBlock += dt }
        if stage == .ready { readyLeft -= dt; if readyLeft <= 0 { space() } }
    }
}

// Fake summary rows.
struct ProtoRow: Identifiable { let id = UUID(); let drill: ProtoDrill; let time, prompts, accuracy, median, skips: String }
let protoRows: [ProtoRow] = [
    .init(drill: .fretName, time: "7:30", prompts: "64", accuracy: "92%", median: "1.8 s", skips: "0"),
    .init(drill: .play, time: "9:30", prompts: "71", accuracy: "83%", median: "1.4 s", skips: "1"),
    .init(drill: .all, time: "8:05", prompts: "58", accuracy: "88%", median: "1.1 s", skips: "2"),
    .init(drill: .hear, time: "7:30", prompts: "31", accuracy: "61%", median: "4.6 s", skips: "3"),
]
let protoSlow = ["E♭ on string 2 (B) — timed out", "A on string 3 (G) — 8.2 s · played G, B first", "F on string 5 (A) — 6.9 s"]

// MARK: - Host and floating bar

struct PrototypeSessionRoot: View {
    @AppStorage("proto.sessionVariant4") private var variant = "S4"
    @State private var s = ProtoSession()
    static let variants = [("S1", "Stage"), ("S2", "Focus"), ("S3", "Agenda"), ("S4", "Combined")]

    var body: some View {
        ZStack(alignment: .bottom) {
            PrototypeSessionVariant(key: variant, s: s).padding(.bottom, 58)
            bar.padding(.bottom, 10)
            shortcuts
        }
        .navigationTitle("Session")
        .navigationSubtitle("Standard tuning")
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                s.tick(0.1)
            }
        }
    }

    private func cycle(_ by: Int) {
        let i = Self.variants.firstIndex { $0.0 == variant } ?? 0
        variant = Self.variants[(i + by + Self.variants.count) % Self.variants.count].0
    }

    private var bar: some View {
        HStack(spacing: 10) {
            Button { cycle(-1) } label: { Image(systemName: "chevron.left") }.keyboardShortcut(.leftArrow, modifiers: [])
            Text("\(variant) (\(Self.variants.first { $0.0 == variant }?.1 ?? ""))").bold().frame(width: 92)
            Button { cycle(1) } label: { Image(systemName: "chevron.right") }.keyboardShortcut(.rightArrow, modifiers: [])
            Divider().frame(height: 16)
            ForEach(ProtoStage.allCases, id: \.self) { stage in
                Button(stage.rawValue) { if stage == .ready { s.ready() } else { s.stage = stage } }
                    .opacity(s.stage == stage ? 1 : 0.55)
            }
            Divider().frame(height: 16)
            Button("Drill ▸") { s.index = (s.index + 1) % s.blocks.count; s.result = .waiting; s.typed = "" }
            ForEach(ProtoResult.allCases, id: \.self) { r in
                Button(r.rawValue) { s.result = r }.opacity(s.result == r ? 1 : 0.55)
            }
            Divider().frame(height: 16)
            Button("0:33 left") { s.elapsedInBlock = s.length(s.index) - 33 }
            Button("Overtime") { s.elapsedInBlock = s.length(s.index) + 12 }
        }
        .buttonStyle(.plain).font(.caption).foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Capsule().fill(.black.opacity(0.85)))
        .fixedSize()
    }

    private var shortcuts: some View {
        Group {
            Button("") { s.space() }.keyboardShortcut(.space, modifiers: [])
            Button("") { s.pause() }.keyboardShortcut("p", modifiers: [])
            Button("") { s.pause() }.keyboardShortcut(.escape, modifiers: [])
            Button("") { s.skip() }.keyboardShortcut("s", modifiers: [])
            Button("") { s.repeatIt() }.keyboardShortcut("r", modifiers: [])
            Button("") { s.extend() }.keyboardShortcut("+", modifiers: [])
            Button("") { s.extend() }.keyboardShortcut("=", modifiers: [])
            Button("") { s.enter() }.keyboardShortcut(.return, modifiers: [])
            if s.stage == .playing && s.drill == .fretName {
                ForEach(["a", "b", "c", "d", "e", "f", "g", "#"], id: \.self) { k in
                    Button("") { s.type(k) }.keyboardShortcut(KeyEquivalent(Character(k)), modifiers: k == "#" ? .shift : [])
                }
            }
        }
        .buttonStyle(.plain).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
}

struct PrototypeSessionVariant: View {
    let key: String
    let s: ProtoSession
    var body: some View {
        switch key {
        case "S2": SessionS2(s: s)
        case "S3": SessionS3(s: s)
        case "S4": SessionS4(s: s)
        default: SessionS1(s: s)
        }
    }
}
#endif
