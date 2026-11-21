// PROTOTYPE — throwaway. Three Note → play it drill layouts for the Phase 1 screen prototype.

import SwiftUI
import TheoryCore

#if DEBUG

// MARK: - Shared drill bits

private struct DrillOptions: View {
    @Bindable var listen: ProtoListen

    var body: some View {
        Picker("Notes", selection: $listen.naturalsOnly) {
            Text("Naturals").tag(true)
            Text("All notes").tag(false)
        }
        Picker("Frets", selection: $listen.maxFret) {
            Text("0–12").tag(12)
            Text("0–22").tag(22)
        }
        Menu("Strings: \(listen.strings.count == 6 ? "all" : listen.strings.sorted().map { "\(listen.tuning.stringNumber(ofString: $0))" }.joined(separator: " "))") {
            ForEach(listen.tuning.strings, id: \.self) { s in
                Toggle(listen.stringLabel(s).capitalizedFirstProto, isOn: Binding(
                    get: { listen.strings.contains(s) },
                    set: { on in if on { listen.strings.insert(s) } else if listen.strings.count > 1 { listen.strings.remove(s) } }))
            }
        }
        Picker("Order", selection: $listen.inOrder) {
            Text("Random").tag(false)
            Text("In order (check)").tag(true)
        }
    }
}

private struct StartStop: View {
    let listen: ProtoListen
    var body: some View {
        if listen.running {
            Button(listen.phase == .paused ? "Resume" : "Pause") { listen.togglePause() }
                .keyboardShortcut("p", modifiers: [])
            Button("Stop") { listen.stop() }.keyboardShortcut(.escape, modifiers: [])
        } else {
            Button("Start") { listen.start() }.keyboardShortcut(.return, modifiers: []).buttonStyle(.borderedProminent)
        }
    }
}

/// "You played G" / "Correct" / "Time's up" line.
private struct Feedback: View {
    let listen: ProtoListen
    var big = false
    var body: some View {
        Group {
            switch listen.phase {
            case .wrong(let n): Label("You played \(n)", systemImage: "xmark.circle.fill").foregroundStyle(.red)
            case .correct(let loc): Label("Fret \(loc.fret) · \(String(format: "%.2f s", listen.attempts.last?.time ?? 0))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .timedOut: Label("Time's up — here it is", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange)
            case .paused: Label("Paused", systemImage: "pause.circle").foregroundStyle(.secondary)
            case .waiting: Label("Listening…", systemImage: "waveform").foregroundStyle(.secondary)
            case .idle: Text(" ")
            }
        }
        .font(big ? .title2.weight(.medium) : .callout.weight(.medium))
    }
}

private struct PromptTimer: View {
    let listen: ProtoListen
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            let active = listen.phase == .waiting || listen.isWrong
            Text(active ? String(format: "%.1f s", listen.elapsed) : " ")
                .font(.title3.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

private struct TimeoutRing: View {
    let listen: ProtoListen
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            let active = listen.phase == .waiting || listen.isWrong
            let f = active ? min(1, listen.elapsed / listen.timeout) : 0
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                Circle().trim(from: 0, to: 1 - f).stroke(f > 0.7 ? Color.orange : Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(active ? String(format: "%.1f", listen.elapsed) : "").font(.callout.monospacedDigit())
            }
        }
    }
}

private struct RunSummary: View {
    let listen: ProtoListen
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(listen.inOrder ? "Check run" : "Run summary").font(.headline)
            HStack(spacing: 28) {
                stat("Prompts", "\(listen.attempts.count)")
                stat("First-try right", listen.accuracy.map { "\(Int($0 * 100))%" } ?? "–")
                stat("Median time", listen.medianTime.map { String(format: "%.2f s", $0) } ?? "–")
                stat("Timed out", "\(listen.attempts.filter { $0.time == nil }.count)")
            }
            if !listen.slowest.isEmpty {
                Text("Slowest").font(.subheadline.weight(.semibold)).padding(.top, 4)
                ForEach(listen.slowest) { a in
                    Text("\(a.prompt.pitchClass.sharpName) on \(listen.stringLabel(a.prompt.string)) — \(a.time.map { String(format: "%.2f s", $0) } ?? "timed out")\(a.wrongNotes.isEmpty ? "" : " · played \(a.wrongNotes.joined(separator: ", ")) first")")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.monospacedDigit().weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct DrillNeck: View {
    let listen: ProtoListen
    var body: some View {
        FretboardView(diagram: listen.drillDiagram)
            .overlay { if listen.running { ProtoStringBand(string: listen.prompt.string, stringCount: 6) } }
    }
}

// MARK: - D1: Prompt over neck — Explorer A2 language: options in the toolbar, prompt header, neck card, stats in the status bar

struct DrillD1: View {
    @Bindable var listen: ProtoListen
    @State private var showSummary = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(listen.running ? listen.promptText : "Note → play it")
                        .font(.system(size: 34, weight: .semibold))
                    if listen.running { Feedback(listen: listen) } else {
                        Text("A note name and a string appear; play it. Press Start (↩).").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                PromptTimer(listen: listen)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)

            DrillNeck(listen: listen)
                .frame(height: 250)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
                .padding(.horizontal, 24)

            Spacer(minLength: 16)
            Divider()
            HStack(spacing: 18) {
                Text("\(listen.attempts.count) prompts")
                Text("first-try \(listen.accuracy.map { "\(Int($0 * 100))%" } ?? "–")")
                Text("median \(listen.medianTime.map { String(format: "%.2f s", $0) } ?? "–")")
                Spacer()
                ProtoInputLabel(level: listen.level)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 24).frame(height: 32).background(.bar)
        }
        .toolbar {
            ToolbarItemGroup(placement: .principal) { DrillOptions(listen: listen).disabled(listen.running) }
            ToolbarItemGroup(placement: .primaryAction) { StartStop(listen: listen) }
        }
        .onChange(of: listen.running) { if !listen.running, !listen.attempts.isEmpty { showSummary = true } }
        .sheet(isPresented: $showSummary) {
            VStack(alignment: .trailing) {
                RunSummary(listen: listen)
                Button("Done") { showSummary = false }.keyboardShortcut(.defaultAction)
            }
            .padding(24).frame(width: 520)
        }
    }
}

// MARK: - D2: Flashcard — a setup card before the run; during it one huge prompt, a timeout ring, a strip of recent attempts, a small neck

struct DrillD2: View {
    @Bindable var listen: ProtoListen

    var body: some View {
        Group {
            if listen.running { running } else { setup }
        }
        .toolbar { ToolbarItemGroup(placement: .primaryAction) { StartStop(listen: listen) } }
    }

    private var setup: some View {
        HStack(alignment: .top, spacing: 24) {
            Form {
                Section("Note → play it") { DrillOptions(listen: listen) }
                Section { ProtoInputLabel(level: listen.level) }
            }
            .formStyle(.grouped)
            .frame(width: 340)
            if !listen.attempts.isEmpty {
                RunSummary(listen: listen)
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                    .padding(.top, 20)
            }
            Spacer()
        }
        .padding(24)
    }

    private var running: some View {
        VStack(spacing: 18) {
            Spacer()
            HStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text(listen.prompt.pitchClass.sharpName).font(.system(size: 110, weight: .bold, design: .rounded))
                    Text("on \(listen.stringLabel(listen.prompt.string))").font(.title)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 360, height: 210)
                .background(RoundedRectangle(cornerRadius: 20).fill(backgroundTint))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color(nsColor: .separatorColor)))
                TimeoutRing(listen: listen).frame(width: 70, height: 70)
            }
            Feedback(listen: listen, big: true)
            HStack(spacing: 6) {
                ForEach(listen.attempts.suffix(12)) { a in
                    VStack(spacing: 0) {
                        Text(a.prompt.pitchClass.sharpName).font(.caption.weight(.semibold))
                        Text(a.time.map { String(format: "%.1f", $0) } ?? "—").font(.caption2.monospacedDigit())
                    }
                    .frame(width: 38, height: 34)
                    .background(RoundedRectangle(cornerRadius: 6).fill((a.firstRight ? Color.green : a.time == nil ? .orange : .red).opacity(0.2)))
                }
            }
            .frame(height: 34)
            Spacer()
            DrillNeck(listen: listen).frame(height: 130).padding(.horizontal, 24)
            HStack { ProtoInputLabel(level: listen.level); Spacer(); Text("Esc stop · P pause").font(.caption).foregroundStyle(.secondary) }
                .padding(.horizontal, 24).padding(.bottom, 6)
        }
    }

    private var backgroundTint: Color {
        switch listen.phase {
        case .correct: .green.opacity(0.15)
        case .wrong: .red.opacity(0.12)
        case .timedOut: .orange.opacity(0.15)
        default: Color(nsColor: .controlBackgroundColor)
        }
    }
}

// MARK: - D3: Neck + inspector — the neck fills the window, the prompt is pinned to its string, everything else in a right column

struct DrillD3: View {
    @Bindable var listen: ProtoListen

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                Spacer()
                ZStack(alignment: .topLeading) {
                    DrillNeck(listen: listen)
                        .frame(height: 320)
                    if listen.running { pinnedPrompt }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                Feedback(listen: listen, big: true)
                Spacer()
            }
            .padding(.horizontal, 20)

            Divider()
            inspector.frame(width: 280)
        }
        .toolbar { ToolbarItemGroup(placement: .primaryAction) { StartStop(listen: listen) } }
    }

    private var pinnedPrompt: some View {
        GeometryReader { geo in
            let g = FretboardGeometry(size: CGSize(width: geo.size.width, height: 320), stringCount: 6, lastFret: 22)
            Text(listen.prompt.pitchClass.sharpName + "?")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .padding(.horizontal, 10).padding(.vertical, 2)
                .background(Capsule().fill(Color.yellow))
                .foregroundStyle(.black)
                .position(x: g.neck.maxX - 40, y: g.y(ofString: listen.prompt.string))
        }
        .allowsHitTesting(false)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("Prompt").font(.caption).foregroundStyle(.secondary)
                    Text(listen.running ? listen.promptText : "Not running").font(.title3.weight(.semibold))
                    PromptTimer(listen: listen)
                }
                Divider()
                Form { DrillOptions(listen: listen) }.disabled(listen.running)
                Divider()
                RunSummary(listen: listen)
                Divider()
                Text("Attempts").font(.caption).foregroundStyle(.secondary)
                ForEach(listen.attempts.reversed()) { a in
                    HStack {
                        Image(systemName: a.firstRight ? "checkmark" : a.time == nil ? "clock" : "xmark")
                            .foregroundStyle(a.firstRight ? .green : a.time == nil ? .orange : .red)
                        Text("\(a.prompt.pitchClass.sharpName) · s\(listen.tuning.stringNumber(ofString: a.prompt.string))")
                        Spacer()
                        Text(a.time.map { String(format: "%.2f", $0) } ?? "—").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                Spacer()
                ProtoInputLabel(level: listen.level)
            }
            .padding(16)
        }
    }
}

extension String {
    var capitalizedFirstProto: String { prefix(1).uppercased() + dropFirst() }
}
#endif

#if DEBUG
// MARK: - D4: D1 + D2 — D1's toolbar, neck card, status bar and summary sheet; under the neck,
// D2's flashcard prompt, countdown ring and strip of recent attempts (user's pick, Nov 21).

struct DrillD4: View {
    @Bindable var listen: ProtoListen
    @State private var showSummary = false

    var body: some View {
        VStack(spacing: 0) {
            DrillNeck(listen: listen)
                .frame(height: 210)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
                .padding(.horizontal, 24).padding(.top, 20)

            Spacer(minLength: 12)
            HStack(spacing: 24) {
                flashcard
                TimeoutRing(listen: listen).frame(width: 64, height: 64)
            }
            Feedback(listen: listen, big: true).padding(.top, 10)
            attemptStrip.padding(.top, 10)
            Spacer(minLength: 12)

            Divider()
            HStack(spacing: 18) {
                Text("\(listen.attempts.count) prompts")
                Text("first-try \(listen.accuracy.map { "\(Int($0 * 100))%" } ?? "–")")
                Text("median \(listen.medianTime.map { String(format: "%.2f s", $0) } ?? "–")")
                Spacer()
                ProtoInputLabel(level: listen.level)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 24).frame(height: 32).background(.bar)
        }
        .toolbar {
            ToolbarItemGroup(placement: .principal) { DrillOptions(listen: listen).disabled(listen.running) }
            ToolbarItemGroup(placement: .primaryAction) { StartStop(listen: listen) }
        }
        .onChange(of: listen.running) { if !listen.running, !listen.attempts.isEmpty { showSummary = true } }
        .sheet(isPresented: $showSummary) {
            VStack(alignment: .trailing) {
                RunSummary(listen: listen)
                Button("Done") { showSummary = false }.keyboardShortcut(.defaultAction)
            }
            .padding(24).frame(width: 520)
        }
    }

    private var flashcard: some View {
        VStack(spacing: 4) {
            if listen.running {
                Text(listen.prompt.pitchClass.sharpName).font(.system(size: 76, weight: .bold, design: .rounded))
                Text("on \(listen.stringLabel(listen.prompt.string))").font(.title2).foregroundStyle(.secondary)
            } else {
                Text("Note → play it").font(.title.weight(.semibold))
                Text("Press Start (↩)").font(.title3).foregroundStyle(.secondary)
            }
        }
        .frame(width: 320, height: 150)
        .background(RoundedRectangle(cornerRadius: 18).fill(tint))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(nsColor: .separatorColor)))
    }

    private var attemptStrip: some View {
        HStack(spacing: 6) {
            ForEach(listen.attempts.suffix(14)) { a in
                VStack(spacing: 0) {
                    Text(a.prompt.pitchClass.sharpName).font(.caption.weight(.semibold))
                    Text(a.time.map { String(format: "%.1f", $0) } ?? "—").font(.caption2.monospacedDigit())
                }
                .frame(width: 38, height: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill((a.firstRight ? Color.green : a.time == nil ? .orange : .red).opacity(0.2)))
                .help(a.wrongNotes.isEmpty ? "" : "Played \(a.wrongNotes.joined(separator: ", ")) first")
            }
        }
        .frame(height: 34)
    }

    private var tint: Color {
        switch listen.phase {
        case .correct: .green.opacity(0.15)
        case .wrong: .red.opacity(0.12)
        case .timedOut: .orange.opacity(0.15)
        default: Color(nsColor: .controlBackgroundColor)
        }
    }
}
#endif
