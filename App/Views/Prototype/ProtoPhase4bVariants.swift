// PROTOTYPE, throwaway: the three Phase 4b variants. See ProtoPhase4b.swift.
import SwiftUI
import PracticeCore
import TheoryCore

private let keyTimes = ["0:48", "0:41", "0:55", "1:02", "0:39", "0:44", "0:58", "0:51", "0:47", "0:40", "0:43", "0:46"]

private struct P4bResult: Identifiable {
    let id: Int
    let result: String
    let versus: String?
}

private let results: [P4bResult] = [
    .init(id: 0, result: "9:12 · 1 wrong", versus: "Best 9:58, 46 s faster"),
    .init(id: 1, result: "24 of 27 right · 2.1 s each", versus: nil),
    .init(id: 2, result: "10:14 · 3 wrong", versus: "Best 11:20, 66 s faster"),
    .init(id: 3, result: "4 passes · 88 → 92 BPM", versus: nil),
    .init(id: 4, result: "8:40 · 5 wrong", versus: "First Triad circle"),
    .init(id: 5, result: "Every chord clean twice · 2:10", versus: nil),
    .init(id: 6, result: "28 of 32 chords clean", versus: nil),
    .init(id: 7, result: "6 min", versus: nil),
]

private let fadeMoves = ["A shape, major: 1 → 3", "E shape, major: 0 → 1", "Root position on D-G-B: 2 → 3", "2nd inversion on D-G-B: 1 → 0"]

private extension P4bModel {
    var keyNames: [String] { circleKeys.map(keyName) }
    var isPlaying: Bool { stepIndex != nil }
}

// MARK: - A · Circle dial: the circle of fifths is the screen's anchor

struct P4bVariantA: View {
    let m: P4bModel
    var body: some View {
        switch m.scene {
        case .setup: setup
        case .summary: summary
        default: playing
        }
    }

    private var setup: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(spacing: 16) {
                P4bDial(keys: m.keyNames, current: 0, size: 300)
                Text("Round the circle from E").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Today’s routine").font(.largeTitle.bold())
                Text("E major · A shape · D-G-B · I–V–vi–IV").font(.title3)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(m.steps) { s in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(s.number)").font(.headline.monospacedDigit()).frame(width: 22)
                            VStack(alignment: .leading) { Text(s.title).font(.headline); Text(s.detail).font(.callout).foregroundStyle(.secondary) }
                            Spacer()
                            Text(s.estimate > 0 ? "~\(s.estimate) min" : "open").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                HStack { Text("About 33 minutes, then free time").foregroundStyle(.secondary); Spacer(); Button("Start") {}.controlSize(.large).keyboardShortcut(.defaultAction) }
            }.frame(maxWidth: 520)
        }.padding(32)
    }

    private var playing: some View {
        HStack(spacing: 28) {
            VStack(spacing: 18) {
                Text("Step \(m.stepIndex! + 1) of 8 · \(m.steps[m.stepIndex!].title)").font(.headline)
                P4bDial(keys: m.keyNames, current: m.circleIndex, size: 250)
                P4bClock(m: m)
            }.frame(width: 300)
            VStack(alignment: .leading, spacing: 12) {
                Text(m.promptTitle).font(.title.bold())
                FretboardView(diagram: m.neck())
                HStack {
                    if m.scene == .triadCircle { Text(m.triadText) }
                    else if m.scene != .noteCircle { Text(m.fadeText) }
                    Spacer()
                    if m.scene != .noteCircle && m.scene != .triadCircle { Text(m.nextText).foregroundStyle(.secondary) }
                }.font(.title3)
            }
        }.padding(28)
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(spacing: 10) {
                Text("Scale circle, per key").font(.headline)
                P4bDial(keys: m.keyNames, current: 12, results: keyTimes, size: 320)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Session done · 41 min").font(.largeTitle.bold())
                ForEach(results) { r in
                    HStack(alignment: .firstTextBaseline) {
                        Text(m.steps[r.id].title).font(.headline).frame(width: 160, alignment: .leading)
                        Text(r.result)
                        Spacer()
                        if let v = r.versus { Text(v).foregroundStyle(.green) }
                    }
                }
                Divider()
                Text("Fade levels").font(.headline)
                ForEach(fadeMoves, id: \.self) { Text($0).foregroundStyle(.secondary) }
            }.frame(maxWidth: 560)
        }.padding(32)
    }
}

// MARK: - B · Progress strip: the session and the circle as two bars across the top

struct P4bVariantB: View {
    let m: P4bModel
    var body: some View {
        VStack(spacing: 0) {
            stepStrip.padding(.horizontal, 20).padding(.top, 14)
            Group {
                switch m.scene {
                case .setup: setup
                case .summary: summary
                default: playing
                }
            }.frame(maxHeight: .infinity)
        }
    }

    private var stepStrip: some View {
        HStack(spacing: 3) {
            ForEach(m.steps) { s in
                let state = m.scene == .summary ? -1 : (m.stepIndex ?? -1) - s.id
                VStack(alignment: .leading, spacing: 3) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(state > 0 || m.scene == .summary ? Color.green : state == 0 ? .orange : .secondary.opacity(0.25))
                        .frame(height: 6)
                    Text(s.title).font(.caption).lineLimit(1).foregroundStyle(state == 0 ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var keyChips: some View {
        HStack(spacing: 6) {
            ForEach(m.walk) { w in
                let i = w.id
                VStack(spacing: 2) {
                    Text(m.keyName(w.key)).font(.headline)
                    if m.scene != .noteCircle && m.scene != .triadCircle {
                        Text(w.ascending ? "↑" : "↓").font(.caption2)
                    }
                }
                .frame(width: 48, height: 40)
                .background(RoundedRectangle(cornerRadius: 6).fill(i < m.circleIndex ? Color.green.opacity(0.25) : i == m.circleIndex ? .orange.opacity(0.4) : .secondary.opacity(0.08)))
                .foregroundStyle(i > m.circleIndex ? .secondary : .primary)
            }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("E major today").font(.system(size: 44, weight: .bold))
            Text("A shape · triads on D-G-B · I–V–vi–IV · round the circle from E").font(.title3).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 10) {
                ForEach(m.steps) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(s.number)").font(.title2.bold().monospacedDigit())
                        Text(s.title).font(.headline)
                        Text(s.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text(s.estimate > 0 ? "~\(s.estimate) min" : "until you stop").font(.caption.monospacedDigit())
                    }
                    .padding(10).frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.08)))
                }
            }
            HStack { Text("About 33 minutes, then free time").font(.title3); Spacer(); Button("Start") {}.controlSize(.large).keyboardShortcut(.defaultAction) }
        }.padding(28)
    }

    private var playing: some View {
        VStack(alignment: .leading, spacing: 14) {
            keyChips
            HStack(alignment: .firstTextBaseline) {
                Text(m.promptTitle).font(.system(size: 34, weight: .bold))
                Spacer()
                P4bClock(m: m)
            }
            FretboardView(diagram: m.neck())
            HStack(spacing: 14) {
                if m.scene == .noteCircle {
                    Text("String 1 (E) · 5 of 6 found").font(.title3)
                } else {
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { l in
                            RoundedRectangle(cornerRadius: 2).fill(l <= m.effectiveLevel ? Color.blue : .secondary.opacity(0.2)).frame(width: 22, height: 10)
                        }
                    }
                    Text(m.scene == .triadCircle ? m.triadText : m.fadeText).font(.title3)
                }
                Spacer()
                if m.scene != .noteCircle && m.scene != .triadCircle { Text(m.nextText).font(.title3).foregroundStyle(.secondary) }
            }
        }.padding(20)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("41 minutes · 8 of 8 steps").font(.system(size: 34, weight: .bold))
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                GridRow { Text("Step").bold(); Text("Result").bold(); Text("Against your best").bold() }
                Divider()
                ForEach(results) { r in
                    GridRow { Text("\(r.id + 1) · \(m.steps[r.id].title)"); Text(r.result); Text(r.versus ?? "").foregroundStyle(.green) }
                }
            }.font(.title3)
            HStack(spacing: 8) {
                Text("Fade levels moved:").font(.headline)
                ForEach(fadeMoves, id: \.self) { Text($0).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(.blue.opacity(0.12))) }
            }
            Spacer()
        }.padding(28)
    }
}

// MARK: - C · Session rail: the whole session down the side, the current key huge, the next position as its own small neck

struct P4bVariantC: View {
    let m: P4bModel
    var body: some View {
        HStack(spacing: 0) {
            rail.frame(width: 250).background(.secondary.opacity(0.06))
            Divider()
            Group {
                switch m.scene {
                case .setup: setup
                case .summary: summary
                default: playing
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(m.scene == .setup ? "Today" : m.scene == .summary ? "Done" : "Session · 18:20").font(.headline).padding(.bottom, 8)
            ForEach(m.steps) { s in
                let state = m.scene == .summary ? 1 : m.scene == .setup ? -1 : m.stepIndex! > s.id ? 1 : m.stepIndex! == s.id ? 0 : -1
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: state > 0 ? "checkmark.circle.fill" : state == 0 ? "play.circle.fill" : "circle")
                        .foregroundStyle(state > 0 ? .green : state == 0 ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.title).font(.callout.weight(state == 0 ? .bold : .regular))
                        if m.scene == .summary { Text(results[s.id].result).font(.caption).foregroundStyle(.secondary) }
                        else if state == 0 { Text("\(m.keyName(m.circleKeys[m.circleIndex])) · \(m.circleIndex + 1) of 12").font(.caption) }
                        else if m.scene == .setup { Text(s.detail).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(state == 0 ? Color.orange.opacity(0.15) : .clear))
            }
            Spacer()
        }.padding(14)
    }

    private var setup: some View {
        VStack(spacing: 18) {
            Text("E").font(.system(size: 110, weight: .bold))
            Text("major · A shape · D-G-B · I–V–vi–IV").font(.title2)
            FretboardView(diagram: FretboardDiagram(m.theme, in: m.key, on: m.fretboard)).frame(height: 220)
            HStack {
                Text("About 33 minutes, then free time").font(.title3).foregroundStyle(.secondary)
                Spacer()
                Button("Start") {}.controlSize(.large).keyboardShortcut(.defaultAction)
            }
        }.padding(28)
    }

    private var playing: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 16) {
                Text(m.keyName(m.circleKeys[m.circleIndex])).font(.system(size: 72, weight: .bold))
                VStack(alignment: .leading) {
                    Text(m.scene == .noteCircle ? "every one, frets 0–12" : m.scene == .triadCircle ? "major · D-G-B · climb" : "\(m.current.position.name) · \(m.current.ascending ? "up ↑" : "down ↓")").font(.title2)
                    Text("\(m.circleIndex + 1) of 12").foregroundStyle(.secondary)
                }
                Spacer()
                P4bClock(m: m)
            }
            FretboardView(diagram: m.neck())
            if m.scene != .noteCircle && m.scene != .triadCircle {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading) {
                        Text(m.fadeText).font(.title3)
                        ProgressView(value: m.effectiveProgress).frame(width: 220)
                        Text("Fade over this pass").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(m.nextText).font(.title3).foregroundStyle(.secondary)
                }
            } else if m.scene == .triadCircle {
                Text(m.triadText + " · " + m.fadeText).font(.title3)
            }
        }.padding(20)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("41 minutes, every step").font(.system(size: 34, weight: .bold))
            Text("Circles against your best").font(.headline)
            HStack(spacing: 20) {
                ForEach([("Note circle", "9:12", "−46 s"), ("Scale circle", "10:14", "−66 s"), ("Triad circle", "8:40", "first")], id: \.0) { c in
                    VStack(alignment: .leading) {
                        Text(c.0).foregroundStyle(.secondary)
                        Text(c.1).font(.system(size: 36, weight: .bold).monospacedDigit())
                        Text(c.2).foregroundStyle(.green)
                    }.padding(14).frame(width: 190, alignment: .leading).background(RoundedRectangle(cornerRadius: 10).fill(.secondary.opacity(0.08)))
                }
            }
            Text("Scale circle per key").font(.headline)
            HStack(spacing: 6) {
                ForEach(0..<12, id: \.self) { i in
                    VStack { Text(m.keyNames[i]).font(.headline); Text(keyTimes[i]).font(.caption.monospacedDigit()) }.frame(width: 52)
                }
            }
            Text("Fade levels").font(.headline)
            ForEach(fadeMoves, id: \.self) { Text($0).foregroundStyle(.secondary) }
            Spacer()
        }.padding(28)
    }
}
