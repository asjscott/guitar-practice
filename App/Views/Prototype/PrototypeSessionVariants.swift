// PROTOTYPE — throwaway. The three session flows; see PrototypeSession.swift.

import SwiftUI
import TheoryCore

#if DEBUG
// MARK: - Small shared parts

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

private struct Neck: View {
    let s: ProtoSession
    var height: CGFloat = 210
    var body: some View {
        Card { FretboardView(diagram: s.diagram).frame(height: height).padding(14) }
    }
}

private struct Feedback: View {
    let s: ProtoSession
    var body: some View {
        let f = s.feedback
        Label(f.text, systemImage: f.icon).font(.title2.weight(.medium)).foregroundStyle(f.color)
    }
}

private struct Keys: View {
    let s: ProtoSession
    var body: some View {
        HStack(spacing: 14) {
            key("Space", "next"); key("P", "pause"); key("S", "skip"); key("+", "2 min")
            if s.drill == .hear { key("R", "replay") }
            if s.drill == .all { key("R", "restart") }
            key("Esc", "end")
        }
        .font(.caption).foregroundStyle(.secondary)
    }
    private func key(_ k: String, _ t: String) -> some View {
        HStack(spacing: 4) {
            Text(k).fontWeight(.semibold).padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.18)))
            Text(t)
        }
    }
}

private struct Difficulty: View {
    @Bindable var s: ProtoSession
    var body: some View {
        Picker("Notes", selection: $s.naturals) { Text("Naturals").tag(true); Text("All notes").tag(false) }.pickerStyle(.segmented)
        Picker("Frets", selection: $s.firstFrets) { Text("First 12 frets").tag(true); Text("Whole neck").tag(false) }.pickerStyle(.segmented)
    }
}

/// All instances: one column per string, filled as each location is found.
private struct SweepChips: View {
    let s: ProtoSession
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(s.sweep.enumerated()), id: \.offset) { i, loc in
                VStack(spacing: 0) {
                    Text("\(s.fretboard.tuning.stringNumber(ofString: loc.string))").font(.caption.weight(.semibold))
                    Text(i < s.foundCount ? "fret \(loc.fret)" : "–").font(.caption2)
                }
                .frame(width: 52, height: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill(i < s.foundCount ? Color.green.opacity(0.2) : i == s.foundCount ? Color.accentColor.opacity(0.25) : .secondary.opacity(0.08)))
            }
        }
    }
}

// MARK: - S1 Stage: D4 plus a block bar along the top; every stage is the same stage

struct SessionS1: View {
    @Bindable var s: ProtoSession
    var body: some View {
        switch s.stage {
        case .setup: setup
        case .summary: summary
        default: player
        }
    }

    var blockBar: some View {
        HStack(spacing: 6) {
            ForEach(Array(s.blocks.enumerated()), id: \.offset) { i, d in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(d.rawValue, systemImage: d.icon).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(i == s.index ? s.timeText : ProtoSession.clock(s.length(i))).monospacedDigit()
                            .foregroundStyle(i == s.index && s.overtime ? .orange : .primary)
                    }
                    .font(.caption.weight(i == s.index ? .semibold : .regular))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.secondary.opacity(0.2))
                            Capsule().fill(i == s.index && s.overtime ? Color.orange : .accentColor)
                                .frame(width: g.size.width * (i < s.index ? 1 : i == s.index ? s.fraction : 0))
                        }
                    }
                    .frame(height: 6)
                }
                .opacity(i == s.index ? 1 : 0.6)
            }
            Text("ends \(s.finish)").font(.caption).foregroundStyle(.secondary).padding(.leading, 8)
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }

    private var player: some View {
        VStack(spacing: 0) {
            blockBar
            Divider()
            Neck(s: s, height: 190).padding(.horizontal, 24).padding(.top, 14)
            Spacer(minLength: 8)
            switch s.stage {
            case .ready:
                VStack(spacing: 8) {
                    Text("Next: \(s.drill.rawValue)").font(.title.bold())
                    Text(s.drill.how).font(.title3).foregroundStyle(.secondary)
                    Text("\(ProtoSession.clock(s.length(s.index))) · Space to start · starting in \(Int(s.readyLeft.rounded(.up)))").monospacedDigit()
                    if s.drill.usesKeyboard { Label("Hands to the keyboard", systemImage: "keyboard").foregroundStyle(.orange) }
                }
            case .paused:
                VStack(spacing: 8) {
                    Image(systemName: "pause.circle").font(.system(size: 48))
                    Text("Paused").font(.title.bold())
                    HStack { Button("Resume (P)") { s.pause() }; Button("End session") { s.stage = .summary } }
                }
            default:
                VStack(spacing: 10) {
                    HStack(spacing: 24) {
                    VStack(spacing: 2) {
                        Text(s.headline).font(.system(size: 64, weight: .bold, design: .rounded))
                        Text(s.subline).font(.title3).foregroundStyle(.secondary)
                    }
                    .frame(width: 340, height: 128)
                    .background(RoundedRectangle(cornerRadius: 18).fill(s.tint))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(nsColor: .separatorColor)))
                    ZStack { // the prompt's own timeout, as in D4 (fixed value here)
                        Circle().stroke(.secondary.opacity(0.15), lineWidth: 6)
                        Circle().trim(from: 0, to: 0.64).stroke(Color.accentColor, style: .init(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("6.4").font(.callout.monospacedDigit())
                    }
                    .frame(width: 64, height: 64)
                    }
                    Feedback(s: s)
                    if s.drill == .all { SweepChips(s: s) }
                }
            }
            Spacer(minLength: 8)
            Divider()
            HStack { Keys(s: s); Spacer(); Text("B♭ major · CAGED A shape").font(.caption).foregroundStyle(.secondary) }
                .padding(.horizontal, 24).frame(height: 32).background(.bar)
        }
    }

    private var setup: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Today's session").font(.largeTitle.bold())
                Text("\(Int(s.minutes)) minutes").font(.title2)
                Slider(value: $s.minutes, in: 10...60, step: 5)
                Difficulty(s: s)
                Button("Start (↩)") { s.start() }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            .frame(maxWidth: 420)
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Today's theme").font(.caption).foregroundStyle(.secondary)
                            Text("B♭ major").font(.title.bold())
                            Text("CAGED A shape").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reroll") {}
                    }
                    .padding(16)
                }
                ForEach(Array(s.blocks.enumerated()), id: \.offset) { i, d in
                    Card {
                        HStack {
                            Label(d.rawValue, systemImage: d.icon)
                            Spacer()
                            Text(ProtoSession.clock(s.length(i))).monospacedDigit()
                        }
                        .padding(12)
                    }
                }
            }
        }
        .padding(32).frame(maxHeight: .infinity, alignment: .top)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("32:35 practised").font(.largeTitle.bold())
            Text("B♭ major · CAGED A shape · 224 prompts · 83% first try").foregroundStyle(.secondary)
            Card { SummaryGrid().padding(16) }
            Text("Slowest").font(.headline)
            ForEach(protoSlow, id: \.self) { Text($0).foregroundStyle(.secondary) }
            Button("Done (↩)") { s.stage = .setup }.buttonStyle(.borderedProminent)
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SummaryGrid: View {
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 36, verticalSpacing: 10) {
            GridRow { Text("Block"); Text("Time"); Text("Prompts"); Text("First try"); Text("Median"); Text("Skipped") }
                .font(.caption).foregroundStyle(.secondary)
            ForEach(protoRows) { r in
                GridRow { Label(r.drill.rawValue, systemImage: r.drill.icon); Text(r.time); Text(r.prompts); Text(r.accuracy); Text(r.median); Text(r.skips) }
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - S2 Focus: one big thing, readable from a music stand; the block's time is the frame

struct SessionS2: View {
    @Bindable var s: ProtoSession
    var body: some View {
        switch s.stage {
        case .setup:
            VStack(spacing: 22) {
                Text("B♭ major").font(.system(size: 64, weight: .bold, design: .rounded))
                HStack { Text("CAGED A shape").foregroundStyle(.secondary); Button("Reroll") {} }.font(.title3)
                HStack(spacing: 20) {
                    Button { s.minutes = max(10, s.minutes - 5) } label: { Image(systemName: "minus.circle").font(.largeTitle) }.buttonStyle(.plain)
                    Text("\(Int(s.minutes)) min").font(.system(size: 44, weight: .semibold, design: .rounded)).frame(width: 190)
                    Button { s.minutes = min(60, s.minutes + 5) } label: { Image(systemName: "plus.circle").font(.largeTitle) }.buttonStyle(.plain)
                }
                Button { s.start() } label: { Text("Start ↩").font(.title).padding(.horizontal, 48).padding(.vertical, 8) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Text(s.blocks.map(\.rawValue).joined(separator: "  ·  ") + "  ·  \(ProtoSession.clock(s.baseSeconds)) each").foregroundStyle(.secondary)
                HStack { Difficulty(s: s) }.frame(width: 560).labelsHidden()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .summary:
            VStack(spacing: 24) {
                Text("32:35").font(.system(size: 84, weight: .bold, design: .rounded)).monospacedDigit()
                HStack(spacing: 16) {
                    ForEach(protoRows) { r in
                        Card {
                            VStack(spacing: 4) {
                                Image(systemName: r.drill.icon).font(.title2).foregroundStyle(.secondary)
                                Text(r.accuracy).font(.system(size: 40, weight: .bold, design: .rounded))
                                Text(r.median).font(.title3)
                                Text(r.drill.rawValue).font(.callout)
                                Text("\(r.prompts) prompts · \(r.skips) skipped").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(width: 170, height: 180)
                        }
                    }
                }
                VStack { Text("Slowest").font(.headline); ForEach(protoSlow, id: \.self) { Text($0).foregroundStyle(.secondary) } }
                Button("Done ↩") { s.stage = .setup }.controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            ZStack {
                (s.stage == .playing && s.result != .waiting ? s.tint : .clear).ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        HStack(spacing: 8) {
                            ForEach(s.blocks.indices, id: \.self) { i in
                                Circle().fill(i < s.index ? Color.accentColor : i == s.index ? .accentColor.opacity(0.5) : .secondary.opacity(0.2)).frame(width: 10)
                            }
                        }
                        Text(s.drill.rawValue).font(.headline)
                        Spacer()
                        Text("ends \(s.finish)").foregroundStyle(.secondary)
                        ring
                    }
                    .padding(.horizontal, 28).padding(.top, 12)
                    Spacer(minLength: 0)
                    center
                    Spacer(minLength: 0)
                    if s.stage == .playing {
                        FretboardView(diagram: s.diagram).frame(height: 180).padding(.horizontal, 28)
                    }
                    Keys(s: s).padding(.vertical, 10)
                }
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.15), lineWidth: 6)
            Circle().trim(from: 0, to: 1 - s.fraction).stroke(Color.accentColor, style: .init(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(s.timeText).font(.callout.monospacedDigit().bold()).foregroundStyle(s.overtime ? .orange : .primary)
        }
        .frame(width: 64, height: 64)
    }

    @ViewBuilder var center: some View {
        switch s.stage {
        case .ready:
            VStack(spacing: 10) {
                Image(systemName: s.drill.icon).font(.system(size: 64)).foregroundStyle(.tint)
                Text(s.drill.rawValue).font(.system(size: 56, weight: .bold, design: .rounded))
                Text(s.drill.how).font(.title2).foregroundStyle(.secondary)
                Text("\(Int(s.readyLeft.rounded(.up)))").font(.system(size: 72, weight: .heavy, design: .rounded)).monospacedDigit()
                Text("\(ProtoSession.clock(s.length(s.index))) · Space to start now").foregroundStyle(.secondary)
            }
        case .paused:
            VStack(spacing: 16) {
                Text("Paused").font(.system(size: 72, weight: .bold, design: .rounded))
                HStack { Button("Resume (P)") { s.pause() }; Button("End session") { s.stage = .summary } }.controlSize(.large)
            }
        default:
            VStack(spacing: 2) {
                Text(s.headline).font(.system(size: s.drill == .all ? 84 : 130, weight: .heavy, design: .rounded))
                Text(s.subline).font(.system(size: 30, weight: .medium)).foregroundStyle(.secondary)
                Feedback(s: s).padding(.top, 6)
            }
        }
    }
}

// MARK: - S3 Agenda: a rail that is the plan at setup, progress while playing and the results at the end

struct SessionS3: View {
    @Bindable var s: ProtoSession
    var body: some View {
        HStack(spacing: 0) {
            rail.frame(width: 250)
            Divider()
            main.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text("B♭ major").font(.title2.bold())
                    Text("CAGED A shape").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if s.stage == .setup { Button("Reroll") {}.controlSize(.small) }
            }
            .padding(.bottom, 6)
            ForEach(Array(s.blocks.enumerated()), id: \.offset) { i, d in
                let done = s.stage == .summary || (s.stage != .setup && i < s.index)
                let current = s.stage != .setup && s.stage != .summary && i == s.index
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: done ? "checkmark.circle.fill" : d.icon).foregroundStyle(done ? .green : .primary).frame(width: 20)
                        Text(d.rawValue).fontWeight(current ? .semibold : .regular)
                        Spacer()
                        Text(current ? s.timeText : ProtoSession.clock(s.length(i))).monospacedDigit().foregroundStyle(current && s.overtime ? .orange : .secondary)
                    }
                    if current { ProgressView(value: s.fraction).tint(s.overtime ? .orange : .accentColor) }
                    if done { Text("\(protoRows[i].accuracy) first try · \(protoRows[i].median)").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(current ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
            }
            Spacer()
            Text(s.stage == .summary ? "32:35 practised" : s.stage == .setup ? "\(Int(s.minutes)) minutes" : "Ends about \(s.finish)")
                .font(.headline)
        }
        .padding(16)
        .background(.bar)
    }

    @ViewBuilder private var main: some View {
        switch s.stage {
        case .setup:
            VStack(alignment: .leading, spacing: 18) {
                Text("How long today?").font(.title.bold())
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    ForEach([10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60], id: \.self) { m in
                        Button { s.minutes = Double(m) } label: { Text("\(m)").font(.title2).frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(.plain)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Int(s.minutes) == m ? Color.accentColor.opacity(0.3) : Color(nsColor: .controlBackgroundColor)))
                    }
                }
                Difficulty(s: s)
                Button("Start (↩)") { s.start() }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            .frame(maxWidth: 460)
        case .ready:
            VStack(alignment: .leading, spacing: 12) {
                Text("Block \(s.index + 1) of \(s.blocks.count)").foregroundStyle(.secondary)
                Text(s.drill.rawValue).font(.system(size: 44, weight: .bold))
                Text(s.drill.how).font(.title2)
                ProgressView(value: 5 - max(0, s.readyLeft), total: 5).frame(width: 320)
                Text("Space to start now").foregroundStyle(.secondary)
            }
        case .paused:
            VStack(spacing: 14) {
                Label("Paused", systemImage: "pause.circle").font(.largeTitle.bold())
                HStack { Button("Resume (P)") { s.pause() }; Button("End session") { s.stage = .summary } }
            }
        case .summary:
            VStack(alignment: .leading, spacing: 18) {
                Text("Slowest prompts").font(.title.bold())
                ForEach(protoSlow, id: \.self) { Text($0).font(.title3) }
                Divider()
                Text("224 prompts · 83% first try · 6 skipped").foregroundStyle(.secondary)
                Button("Done (↩)") { s.stage = .setup }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: 560, alignment: .leading)
        case .playing:
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(s.headline).font(.system(size: 60, weight: .bold, design: .rounded))
                    Text(s.subline).font(.title).foregroundStyle(.secondary)
                    Spacer()
                    Feedback(s: s)
                }
                .padding(.horizontal, 18).frame(height: 96)
                .background(RoundedRectangle(cornerRadius: 12).fill(s.tint))
                Neck(s: s, height: 230)
                if s.drill == .all { SweepChips(s: s) }
                Spacer()
                Keys(s: s)
            }
            .padding(18)
        }
    }
}
// MARK: - S4 Combined: S2's setup, Ready, pause and summary; S1's playing layout (drills, neck, target).
// The block bar stays on top through Ready and pause, so nothing jumps between blocks.

struct SessionS4: View {
    let s: ProtoSession
    var body: some View {
        switch s.stage {
        case .setup, .summary: SessionS2(s: s)
        case .playing: SessionS1(s: s)
        case .ready, .paused:
            VStack(spacing: 0) {
                SessionS1(s: s).blockBar
                Divider()
                Spacer(minLength: 8)
                SessionS2(s: s).center
                Spacer(minLength: 8)
                Divider()
                HStack { Keys(s: s); Spacer(); Text("B♭ major · CAGED A shape").font(.caption).foregroundStyle(.secondary) }
                    .padding(.horizontal, 24).frame(height: 32).background(.bar)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
#endif
