// VERDICT (26 Nov 2026): C, session rail. The whole session down the side, the current key huge, the clock and best at the
// top right. No preview of the next position: the neck changes to the next key, fully shown, first note ringed. Necks
// showing a long fret range (Note circle 0–12) keep a real guitar's proportions, not stretched to fill the height.
// PROTOTYPE, throwaway. Three variants of the Phase 4b daily routine screens (spec #64) on one Prototype screen:
// A circle dial, B progress strip, C session rail. Each covers setup, the three circle drills and the summary.
// ← → variant · 1–8 scene · F steps the fade through the pass · L fade level. No audio, nothing saved.
// Question: what should the routine look like: setup with no budget, a circle drill with the fade by time, and the summary?
import Observation
import SwiftUI
import PracticeCore
import TheoryCore

enum P4bVariant: String, CaseIterable {
    case a = "A", b = "B", c = "C"
    var title: String {
        switch self {
        case .a: "Circle dial"
        case .b: "Progress strip"
        case .c: "Session rail"
        }
    }
}

enum P4bScene: String, CaseIterable {
    case setup = "Setup", noteCircle = "Note circle", scaleStart = "Scale: start", scaleFading = "Scale: fading",
         scaleRoots = "Scale: roots only", scaleNext = "Scale: key change", triadCircle = "Triad circle", summary = "Summary"
}

struct P4bStep: Identifiable {
    let id: Int
    let title: String
    let detail: String
    let estimate: Int
    var number: Int { id + 1 }
}

/// One key of the Scale circle: its position and direction.
struct P4bWalkStep: Identifiable {
    let id: Int
    let key: Key
    let position: Position
    let ascending: Bool
    var name: String { "\(key.tonic)\(key.mode == .minor ? "m" : "")" }
}

@MainActor @Observable final class P4bModel {
    var variant = P4bVariant.a
    var scene = P4bScene.scaleFading
    /// How far through the current prompt's expected time, 0–1.
    var progress = 0.45
    /// 0–6.
    var level = 1
    let fretboard = Fretboard(tuning: .standard)
    let key = Key.major(NoteName(.e))
    let theme: Position
    let walk: [P4bWalkStep]
    let stringSet = StringSet.dGB

    static let fadeShares: [Double?] = [nil, 0.9, 0.68, 0.51, 0.38, 0.28, 0]

    let steps: [P4bStep] = [
        .init(id: 0, title: "Note circle", detail: "Every E, then every B, … frets 0–12", estimate: 6),
        .init(id: 1, title: "Fret → name it", detail: "Today’s note drill · 2 min", estimate: 2),
        .init(id: 2, title: "Scale circle", detail: "E major, A shape, round all 12 keys", estimate: 8),
        .init(id: 3, title: "Up and down", detail: "E major, A shape, to the clicks · 1 min", estimate: 1),
        .init(id: 4, title: "Triad circle", detail: "Every inversion on D-G-B, round all 12 keys", estimate: 9),
        .init(id: 5, title: "Chords in position", detail: "I–V–vi–IV in the A shape, no backing", estimate: 3),
        .init(id: 6, title: "Stay in position", detail: "I–V–vi–IV over the backing, rock, 70 BPM", estimate: 4),
        .init(id: 7, title: "Free time", detail: "The backing loops; play what you like", estimate: 0),
    ]

    init(variant: P4bVariant = .a, scene: P4bScene = .scaleFading, progress: Double = 0.45, level: Int = 1) {
        self.variant = variant; self.scene = scene; self.progress = progress; self.level = level
        theme = Theme(key: key, position: Position.ID(system: .caged, number: CAGEDShape.a.number)).position(on: fretboard)!
        walk = Self.makeWalk(fretboard, key: key, theme: theme)
    }

    /// The spec's rule: the next key's root nearest in pitch to the last note, among roots in the theme's frets that a
    /// position holds; of those positions, the one overlapping the theme's frets most.
    private static func makeWalk(_ fb: Fretboard, key: Key, theme: Position) -> [P4bWalkStep] {
        var steps = [P4bWalkStep(id: 0, key: key, position: theme, ascending: true)]
        let range = theme.frets
        for i in 1..<12 {
            let last = steps[i - 1]
            let pitches = last.position.locations.map { fb.pitch(at: $0) }
            let end = last.ascending ? pitches.max()! : pitches.min()!
            let next = Key.app(tonic: last.key.tonic.pitchClass + Interval(7), mode: key.mode)
            let positions = fb.positions(of: next.scale, system: .caged)
            let roots = fb.locations(of: next.tonic.pitchClass).filter { r in
                range.contains(r.fret) && positions.contains { $0.locations.contains(r) }
            }
            let root = roots.min { (abs((fb.pitch(at: $0) - end).semitones), $0.fret) < (abs((fb.pitch(at: $1) - end).semitones), $1.fret) }!
            func overlap(_ p: Position) -> Int { max(0, min(p.frets.upperBound, range.upperBound) - max(p.frets.lowerBound, range.lowerBound) + 1) }
            let position = positions.filter { $0.locations.contains(root) }
                .max { (overlap($0), -$0.frets.lowerBound) < (overlap($1), -$1.frets.lowerBound) }!
            steps.append(P4bWalkStep(id: i, key: next, position: position, ascending: !last.ascending))
        }
        return steps
    }

    // MARK: What the scene shows

    /// The session step that's playing; nil at setup and summary.
    var stepIndex: Int? {
        switch scene {
        case .setup, .summary: nil
        case .noteCircle: 0
        case .triadCircle: 4
        default: 2
        }
    }

    /// Which key of the circle is up.
    var circleIndex: Int {
        switch scene {
        case .noteCircle, .scaleNext: 3
        case .triadCircle: 1
        default: 2
        }
    }

    var circleKeys: [Key] { walk.map(\.key) }
    func keyName(_ k: Key) -> String { "\(k.tonic)\(k.mode == .minor ? "m" : "")" }
    var current: P4bWalkStep { walk[circleIndex] }
        var effectiveLevel: Int { scene == .scaleRoots ? 6 : scene == .scaleStart ? 0 : level }
    var effectiveProgress: Double { scene == .scaleNext ? 0 : scene == .scaleStart ? 0.1 : progress }
    var fadeText: String {
        let l = effectiveLevel
        guard let share = Self.fadeShares[l] else { return "Level 0 · shown" }
        return share == 0 ? "Level 6 · roots only" : "Level \(l) · gone by \(Int(share * 100)) %"
    }

    /// The pass's notes in playing order.
    var passOrder: [FretboardLocation] {
        let sorted = current.position.locations.sorted { fretboard.pitch(at: $0) < fretboard.pitch(at: $1) }
        return current.ascending ? sorted : sorted.reversed()
    }
    var notesPlayed: Int { Int(Double(passOrder.count) * effectiveProgress) }
    var elapsedText: String { scene == .noteCircle ? "2:41" : scene == .triadCircle ? "1:12" : "3:05" }
    var wrongNotes: Int { scene == .noteCircle ? 2 : 1 }
    var bestText: String { scene == .noteCircle ? "Best 9:58" : "Best 11:20" }

    func opacity(fadeAt progress: Double) -> Double {
        guard let share = Self.fadeShares[effectiveLevel] else { return 1 }
        guard share > 0 else { return 0 }
        return max(0, 1 - progress / share)
    }

    func neck(compact: Bool = false) -> FretboardDiagram {
        switch scene {
        case .noteCircle: noteCircleNeck()
        case .triadCircle: triadNeck()
        default: scaleNeck(compact: compact)
        }
    }

    private func scaleNeck(compact: Bool) -> FretboardDiagram {
        let k = current.key
        var d = FretboardDiagram(stringNames: fretboard.stringNames(in: k).map(\.description))
        d.fretWindow = current.position.fretWindow
        let order = passOrder
        let fade = opacity(fadeAt: effectiveProgress)
        for (i, l) in order.enumerated() {
            let isRoot = fretboard.pitch(at: l).pitchClass == k.tonic.pitchClass
            let played = i < notesPlayed
            d.markers.append(.init(location: l, label: fretboard.name(at: l, in: k).description,
                                   role: isRoot ? .root : .tone,
                                   isLastPlayed: notesPlayed == 0 ? i == 0 : played && i == notesPlayed - 1,
                                   opacity: played || isRoot ? 1 : fade))
        }
        return d
    }

    private func noteCircleNeck() -> FretboardDiagram {
        let k = circleKeys[circleIndex]
        var d = FretboardDiagram(stringNames: fretboard.stringNames(in: k).map(\.description))
        d.fretWindow = 0...12
        let found = fretboard.locations(of: k.tonic.pitchClass).filter { $0.fret <= 12 }
            .sorted { ($0.string, $0.fret) < ($1.string, $1.fret) }
        let done = 5
        for (i, l) in found.prefix(done).enumerated() {
            d.markers.append(.init(location: l, label: k.tonic.description, role: .root, isLastPlayed: i == done - 1))
        }
        d.highlightedStrings = [found[min(done, found.count - 1)].string]
        return d
    }

    var triadVoicings: [TriadVoicing] {
        let k = circleKeys[circleIndex]
        let triad = Triad(.major, root: k.tonic)
        return fretboard.voicings(of: triad, on: stringSet, frets: 0...15).sorted { $0.locations.map(\.fret).min()! < $1.locations.map(\.fret).min()! }
    }

    private func triadNeck() -> FretboardDiagram {
        let k = circleKeys[circleIndex]
        var d = FretboardDiagram(stringNames: fretboard.stringNames(in: k).map(\.description))
        d.fretWindow = 0...15
        d.highlightedStrings = Set(stringSet.strings)
        let voicings = triadVoicings
        let v = voicings[min(2, voicings.count - 1)]
        let fade = opacity(fadeAt: progress)
        for (i, l) in fretboard.locationsLowToHigh(of: v).enumerated() {
            let isRoot = fretboard.pitch(at: l).pitchClass == k.tonic.pitchClass
            d.markers.append(.init(location: l, label: fretboard.name(at: l, in: k).description, role: isRoot ? .root : .tone,
                                   isLastPlayed: i == 0, opacity: i == 0 || isRoot ? 1 : fade))
        }
        return d
    }

    var triadText: String {
        let voicings = triadVoicings
        return "\(keyName(circleKeys[circleIndex])) · voicing 3 of \(voicings.count * 2 - 1) · up"
    }

    var promptTitle: String {
        switch scene {
        case .noteCircle: "Every \(circleKeys[circleIndex].tonic)"
        case .triadCircle: "\(keyName(circleKeys[circleIndex])) major on D-G-B"
        default: "\(current.name) major · \(current.position.name) · \(current.ascending ? "up ↑" : "down ↓")"
        }
    }

    var nextText: String {
        let n = walk[min(11, circleIndex + 1)]
        return "Next: \(n.name) · \(n.position.name) · \(n.ascending ? "up" : "down")"
    }
}

struct P4bScreen: View {
    @State var model: P4bModel
    var showsSwitcher = true

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.variant {
                case .a: P4bVariantA(m: model)
                case .b: P4bVariantB(m: model)
                case .c: P4bVariantC(m: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 12) {
                ForEach(["Space next block", "S skip", "H hint", "Esc end session"], id: \.self) { Text($0) }
                Spacer()
                Text("Today: E major · A shape · D-G-B · I–V–vi–IV")
            }.sessionStatusBar()
        }
        .overlay(alignment: .bottom) { if showsSwitcher { switcher.padding(.bottom, 44) } }
        .onPlainKey { key in
            switch key {
            case .character("\u{f702}"): cycle(-1); return true
            case .character("\u{f703}"): cycle(1); return true
            case .character("f"): model.progress = model.progress >= 1 ? 0 : min(1, model.progress + 0.15); return true
            case .character("l"): model.level = (model.level + 1) % 7; return true
            case .character(let c):
                guard let n = Int(c), P4bScene.allCases.indices.contains(n - 1) else { return false }
                model.scene = P4bScene.allCases[n - 1]
                return true
            default: return false
            }
        }
    }

    private func cycle(_ by: Int) {
        let all = P4bVariant.allCases
        model.variant = all[(all.firstIndex(of: model.variant)! + by + all.count) % all.count]
    }

    private var switcher: some View {
        HStack(spacing: 10) {
            Button("←") { cycle(-1) }
            Text("\(model.variant.rawValue) · \(model.variant.title)").frame(width: 170)
            Button("→") { cycle(1) }
            Picker("", selection: $model.scene) {
                ForEach(Array(P4bScene.allCases.enumerated()), id: \.element) { Text("\($0.offset + 1) \($0.element.rawValue)").tag($0.element) }
            }.frame(width: 170)
            Slider(value: $model.progress, in: 0...1).frame(width: 120)
            Stepper("Level \(model.level)", value: $model.level, in: 0...6)
        }
        .buttonStyle(.plain).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 8)
        .background(Capsule().fill(.purple)).shadow(radius: 6).environment(\.colorScheme, .dark)
    }
}

// MARK: - Shared bits (data only; each variant has its own layout)

/// The twelve keys of the circle placed round a ring: done, current and to come.
struct P4bDial: View {
    let keys: [String]
    let current: Int
    var results: [String]? = nil
    var size: CGFloat = 260

    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.25), lineWidth: 2)
            ForEach(keys.indices, id: \.self) { i in
                let angle = Angle.degrees(Double(i) * 30 - 90)
                let r = size / 2 - 26
                VStack(spacing: 0) {
                    Text(keys[i]).font(.system(size: i == current ? 22 : 16, weight: i == current ? .bold : .regular))
                    if let results { Text(results[i]).font(.caption2).foregroundStyle(.secondary) }
                }
                .frame(width: 46, height: 46)
                .background(Circle().fill(i < current ? Color.green.opacity(0.25) : i == current ? Color.orange.opacity(0.35) : .clear))
                .foregroundStyle(i > current && results == nil ? .secondary : .primary)
                .offset(x: r * cos(angle.radians), y: r * sin(angle.radians))
            }
        }
        .frame(width: size, height: size)
    }
}

struct P4bClock: View {
    let m: P4bModel
    var body: some View {
        HStack(spacing: 18) {
            Label(m.elapsedText, systemImage: "stopwatch").monospacedDigit()
            Label("\(m.wrongNotes) wrong", systemImage: "xmark.circle").foregroundStyle(m.wrongNotes > 0 ? .orange : .secondary)
            Text(m.bestText).foregroundStyle(.secondary)
        }.font(.title3)
    }
}
