// VERDICT (25 Nov 2026): B, provisionally. Neck + scrolling timeline past a playhead; the next voicing ghosted on the neck
// while Shown; Target top note as a line over the blocks. The player will judge it in use with the backing; A (chord row) is the fallback.
// PROTOTYPE, throwaway. Three variants of the Phase 4 Progressions drill screen (A, B, C) on one Prototype screen.
// ← → variant · 1–5 scene · D drill · G progression · T next time through · Space plays or stops. No audio, nothing saved.
// Question: what should a progression drill look like while the backing runs, with a run-scoped fade and a score per chord?
import Observation
import SwiftUI
import PracticeCore
import TheoryCore

enum P4Variant: String, CaseIterable {
    case a = "A", b = "B", c = "C"
    var title: String {
        switch self {
        case .a: "Neck + chord row"
        case .b: "Neck + scrolling timeline"
        case .c: "Lead sheet of small necks"
        }
    }
}

enum P4Scene: String, CaseIterable { case setup, countIn, playing, wrong, summary }

enum P4Drill: String, CaseIterable {
    case nearest = "Nearest voicing", stay = "Stay in position", top = "Target top note"
}

enum P4Stage: String { case shown = "Shown", faded = "Faded", hidden = "Hidden" }

enum P4Outcome { case clean, wrong, missed }

enum P4Progression: String, CaseIterable {
    case pop = "I–V–vi–IV", twoFive = "ii–V–I", blues = "12-bar blues"
    /// Degree from the tonic (0-based), numeral, bars.
    var steps: [(degree: Int, numeral: String, bars: Int)] {
        switch self {
        case .pop: [(0, "I", 1), (4, "V", 1), (5, "vi", 1), (3, "IV", 1)]
        case .twoFive: [(1, "ii", 1), (4, "V", 1), (0, "I", 2)]
        case .blues: [0, 0, 0, 0, 3, 3, 0, 0, 4, 3, 0, 4].map { ($0, ["I", "", "", "IV", "V"][$0], 1) }
        }
    }
    var style: String { self == .blues ? "Blues shuffle" : "Rock" }
}

struct P4Chord: Identifiable {
    let id: Int
    let numeral: String
    let triad: Triad
    let bars: Int
    /// Beat of the time through it starts on, from 0.
    let start: Int
    let voicing: TriadVoicing?
    var beats: Int { bars * 4 }
    var name: String { triad.quality == .major ? triad.root.description : "\(triad.root)m" }
}

@MainActor @Observable final class P4Model {
    var variant = P4Variant.a
    var scene = P4Scene.playing
    var drill = P4Drill.nearest { didSet { rebuild() } }
    var progression = P4Progression.pop { didSet { rebuild() } }
    /// From 1.
    var timeThrough = 1 { didSet { rebuild() } }
    /// Beat of the time through, from 0.
    var beat = 6
    var playing = false
    let bpm = 70
    let fretboard = Fretboard(tuning: .standard)
    let key = Key.major(.g)
    let position: Position
    let positionSet: Set<FretboardLocation>
    private(set) var chords: [P4Chord] = []

    init(variant: P4Variant = .a, scene: P4Scene = .playing, drill: P4Drill = .nearest,
         progression: P4Progression = .pop, timeThrough: Int = 1, beat: Int = 6) {
        position = Theme(key: key, position: Position.ID(system: .caged, number: CAGEDShape.e.number)).position(on: fretboard)!
        positionSet = Set(position.locations)
        self.variant = variant; self.scene = scene; self.drill = drill; self.progression = progression
        self.timeThrough = timeThrough; self.beat = beat
        rebuild()
    }

    var stage: P4Stage { timeThrough <= 2 ? .shown : timeThrough <= 4 ? .faded : .hidden }
    var totalBeats: Int { chords.reduce(0) { $0 + $1.beats } }
    var current: P4Chord? { scene == .countIn ? nil : chords.last { $0.start <= beat } }
    var currentIndex: Int { current?.id ?? -1 }
    var beatInBar: Int { scene == .countIn ? beat % 4 : beat % 4 }
    var stringSetOfRun: StringSet? { drill == .stay ? stayStringSets[(timeThrough - 1) % stayStringSets.count] : nil }
    var fretWindow: ClosedRange<Int> { position.fretWindow }
    var progressionText: String { chords.map(\.name).joined(separator: " ") }

    /// Notes of a chord played so far: one a beat from its start.
    func notesPlayed(_ chord: P4Chord) -> Int {
        guard scene != .countIn else { return 0 }
        if chord.id < currentIndex { return 3 }
        if chord.id > currentIndex { return 0 }
        return min(3, beat - chord.start + 1)
    }

    func outcome(_ chord: P4Chord) -> P4Outcome? {
        guard chord.id < currentIndex, scene != .countIn else { return nil }
        if scene == .wrong && chord.id == currentIndex - 1 { return .wrong }
        if timeThrough >= 5 && chord.id == 0 { return .missed }
        return .clean
    }

    var feedback: (String, Color)? {
        switch scene {
        case .wrong: ("Wrong note in \(chords[max(0, currentIndex - 1)].name)", .orange)
        case .playing where currentIndex > 0: ("\(chords[currentIndex - 1].name) clean", .green)
        default: nil
        }
    }

    func pitches(_ v: TriadVoicing) -> [Int] { v.locations.map { fretboard.pitch(at: $0).midi } }
    func name(_ l: FretboardLocation) -> String { fretboard.name(at: l, in: key).description }
    func topName(_ chord: P4Chord) -> String { chord.voicing.flatMap { $0.locations.last }.map(name) ?? "–" }

    private var stayStringSets: [StringSet] { [.eAD, .aDG, .dGB, .gBE] }

    private func candidates(_ triad: Triad, on sets: [StringSet]) -> [TriadVoicing] {
        sets.flatMap { set in
            Triad.Inversion.allCases.flatMap { fretboard.voicings(of: triad, inversion: $0, on: set) }
        }
        .filter { $0.locations.allSatisfy(positionSet.contains) }
    }

    private func movement(_ a: TriadVoicing, _ b: TriadVoicing) -> Int {
        zip(pitches(a), pitches(b)).reduce(0) { $0 + abs($1.0 - $1.1) }
    }

    private func rebuild() {
        let mid = Double(position.fretWindow.lowerBound + position.fretWindow.upperBound) / 2
        let sets = stringSetOfRun.map { [$0] } ?? StringSet.allCases
        var previous: TriadVoicing?
        var start = 0
        chords = progression.steps.enumerated().map { index, step in
            let triad = key.chords[step.degree]
            let all = candidates(triad, on: sets)
            let chosen: TriadVoicing?
            switch (drill, previous) {
            case (.top, nil):
                chosen = all.filter { $0.locations.last.map { fretboard.pitch(at: $0).pitchClass } == triad.root.pitchClass }
                    .max { pitches($0)[2] < pitches($1)[2] } ?? all.first
            case (.top, let p?):
                let top = pitches(p)[2]
                chosen = all.min { (abs(pitches($0)[2] - top), movement($0, p)) < (abs(pitches($1)[2] - top), movement($1, p)) }
            case (_, nil):
                chosen = all.min {
                    abs(Double($0.frets.lowerBound + $0.frets.upperBound) / 2 - mid) < abs(Double($1.frets.lowerBound + $1.frets.upperBound) / 2 - mid)
                }
            case (_, let p?):
                chosen = all.min { movement($0, p) < movement($1, p) }
            }
            previous = chosen ?? previous
            defer { start += step.bars * 4 }
            return P4Chord(id: index, numeral: step.numeral, triad: triad, bars: step.bars, start: start, voicing: chosen)
        }
        beat = min(beat, max(0, totalBeats - 1))
    }

    /// The neck for one chord: its voicing faded by the run's stage, with the notes played so far solid.
    func diagram(for chord: P4Chord?, window: ClosedRange<Int>? = nil, preview: P4Chord? = nil, backdrop: Bool = false) -> FretboardDiagram {
        var d = FretboardDiagram(stringNames: fretboard.stringNames(in: key).map(\.description))
        d.fretWindow = window ?? fretWindow
        if backdrop {
            d.markers = position.locations.map { .init(location: $0, label: "", role: .tone, isFaint: true) }
        }
        if let set = stringSetOfRun { d.highlightedStrings = Set(set.strings) }
        if let p = preview?.voicing, stage == .shown {
            d.markers += p.locations.map { .init(location: $0, label: "", role: .tone, isFaint: true) }
        }
        guard let chord, let v = chord.voicing else { return d }
        if stringSetOfRun == nil, stage != .hidden { d.highlightedStrings = Set(v.stringSet.strings) }
        let played = notesPlayed(chord)
        d.markers.removeAll { v.locations.contains($0.location) }
        for (i, l) in v.locations.enumerated() {
            let role: FretboardDiagram.Role = fretboard.pitch(at: l).pitchClass == chord.triad.root.pitchClass ? .root : .tone
            if i < played {
                d.markers.append(.init(location: l, label: name(l), role: role, isLastPlayed: i == played - 1 && chord.id == currentIndex))
            } else if stage == .shown {
                d.markers.append(.init(location: l, label: name(l), role: role))
            } else if stage == .faded {
                d.markers.append(.init(location: l, label: "", role: role, isFaint: true))
            }
        }
        if scene == .wrong, chord.id == currentIndex - 1 || (chord.id == currentIndex && currentIndex == 0), let l = v.locations.dropFirst().first {
            d.markers.append(.init(location: FretboardLocation(string: l.string, fret: l.fret + 1), label: "✕", role: .tone, isLastPlayed: true))
        }
        return d
    }

    func run() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60.0 / Double(bpm)))
            guard playing else { continue }
            if scene == .countIn {
                if beat >= 3 { scene = .playing; beat = 0 } else { beat += 1 }
            } else if beat + 1 >= totalBeats {
                beat = 0; timeThrough += 1
            } else {
                beat += 1
            }
        }
    }
}

struct P4Screen: View {
    @State var model: P4Model
    var showsSwitcher = true

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.scene {
                case .setup: P4Setup(m: model)
                case .summary: P4Summary(m: model)
                default:
                    switch model.variant {
                    case .a: P4VariantA(m: model)
                    case .b: P4VariantB(m: model)
                    case .c: P4VariantC(m: model)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            P4StatusBar(m: model)
        }
        .overlay(alignment: .bottom) { if showsSwitcher { switcher.padding(.bottom, 44) } }
        .task { await model.run() }
        .onPlainKey { key in
            switch key {
            case .space: model.playing.toggle(); return true
            case .character("\u{f702}"): cycle(-1); return true
            case .character("\u{f703}"): cycle(1); return true
            case .character("d"):
                let all = P4Drill.allCases; model.drill = all[(all.firstIndex(of: model.drill)! + 1) % all.count]; return true
            case .character("g"):
                let all = P4Progression.allCases; model.progression = all[(all.firstIndex(of: model.progression)! + 1) % all.count]; return true
            case .character("t"): model.timeThrough += 1; return true
            case .character(let c):
                guard let n = Int(c), P4Scene.allCases.indices.contains(n - 1) else { return false }
                model.scene = P4Scene.allCases[n - 1]
                if model.scene == .countIn { model.beat = 1 }
                return true
            default: return false
            }
        }
    }

    private func cycle(_ by: Int) {
        let all = P4Variant.allCases
        model.variant = all[(all.firstIndex(of: model.variant)! + by + all.count) % all.count]
    }

    private var switcher: some View {
        HStack(spacing: 10) {
            Button("←") { cycle(-1) }
            Text("\(model.variant.rawValue) · \(model.variant.title)").frame(width: 200)
            Button("→") { cycle(1) }
            Picker("", selection: $model.scene) {
                ForEach(Array(P4Scene.allCases.enumerated()), id: \.element) { Text("\($0.offset + 1) \($0.element.rawValue)").tag($0.element) }
            }.frame(width: 120)
            Picker("", selection: $model.drill) { ForEach(P4Drill.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 150)
            Picker("", selection: $model.progression) { ForEach(P4Progression.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 120)
            Stepper("Time \(model.timeThrough) · \(model.stage.rawValue)", value: $model.timeThrough, in: 1...9)
            Button(model.playing ? "Stop" : "Play") { model.playing.toggle() }
        }
        .buttonStyle(.plain).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 8)
        .background(Capsule().fill(.purple)).shadow(radius: 6).environment(\.colorScheme, .dark)
    }
}

// MARK: - Shared bits (data and chrome only; each variant has its own layout)

struct P4Beats: View {
    let m: P4Model
    var size: CGFloat = 20
    var body: some View {
        HStack(spacing: size * 0.25) {
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(i == m.beatInBar ? Color.orange : i == 0 ? .blue : .secondary.opacity(0.3))
                    .frame(width: i == 0 ? size : size * 0.6, height: i == 0 ? size : size * 0.6)
            }
        }
    }
}

extension P4Outcome {
    var color: Color {
        switch self {
        case .clean: .green
        case .wrong: .orange
        case .missed: .gray
        }
    }
}

struct P4StatusBar: View {
    let m: P4Model
    var body: some View {
        HStack(spacing: 12) {
            ForEach(["Space start", "P pause", "Esc end", "+ extend"], id: \.self) { Text($0) }
            Spacer()
            Label("♩ = \(m.bpm) · \(m.progression.style)", systemImage: "music.note")
            Text("G major · E shape · \(m.progression.rawValue)")
        }.sessionStatusBar()
    }
}

/// Setup in free practice: the same for every variant.
struct P4Setup: View {
    @Bindable var m: P4Model
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(m.drill.rawValue).font(.largeTitle.bold())
            Text(blurb).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow { Text("Key").foregroundStyle(.secondary); Text("G major").font(.title3.bold()) }
                GridRow { Text("Position").foregroundStyle(.secondary); Text("E shape, frets \(m.fretWindow.lowerBound)–\(m.fretWindow.upperBound)") }
                GridRow {
                    Text("Progression").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(P4Progression.allCases, id: \.self) { p in
                            Button { m.progression = p } label: {
                                HStack {
                                    Image(systemName: m.progression == p ? "largecircle.fill.circle" : "circle")
                                    Text(p.rawValue).frame(width: 110, alignment: .leading)
                                    Text(p == m.progression ? m.progressionText : "").foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                GridRow { Text("Style").foregroundStyle(.secondary); Picker("", selection: .constant(m.progression.style)) { ForEach(["Rock", "Pop ballad", "Blues shuffle"], id: \.self) { Text($0) } }.pickerStyle(.segmented).frame(width: 320) }
                GridRow { Text("Tempo").foregroundStyle(.secondary); Text("♩ = \(m.bpm)") }
            }
            Label("The backing must not reach the guitar’s input: use the interface, or headphones.", systemImage: "headphones")
                .foregroundStyle(.secondary)
            Button("Start ↩") {}.keyboardShortcut(.defaultAction).controlSize(.large)
            Spacer()
        }
        .padding(32).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var blurb: String {
        switch m.drill {
        case .nearest: "Each chord on the voicing nearest the one before, anywhere in the position. Arpeggiate low to high, in time."
        case .stay: "Every chord inside the position, on one string set per time through."
        case .top: "Keep the top notes a smooth line, anywhere in the position."
        }
    }
}

/// End of a block, the same for every variant.
struct P4Summary: View {
    let m: P4Model
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(m.drill.rawValue).font(.headline)
            Text("31 of 40 chords clean").font(.system(size: 40, weight: .bold, design: .rounded))
            Text("10 times through · Hidden from the 5th · 6 wrong, 3 missed").foregroundStyle(.secondary)
            Text("Hardest: Em (4 of 10), C (6 of 10)").foregroundStyle(.secondary)
        }
        .padding(24).sessionCard().padding(40).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
