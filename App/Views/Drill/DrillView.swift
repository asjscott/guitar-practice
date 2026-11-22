import PracticeCore
import SwiftUI
import TheoryCore

/// The Note → play it drill screen, D4: options in the toolbar with Start (↩), Pause/Resume (P) and Stop (Esc);
/// the neck card with the target string lit; under it a flashcard tinted by result, a 10 s countdown ring, a
/// feedback line and a strip of recent attempts; a status bar with running stats and the input meter; a summary
/// sheet on Stop. A listening screen: audio input runs while it is open, and leaving it ends the run.
/// Follows the tuning and capo in Settings.
struct DrillView: View {
    @State private var model = DrillViewModel()
    @State private var showSummary = false
    @Environment(AudioInputService.self) private var audioInput
    @AppStorage(InstrumentSettings.Key.openPitches) private var storedOpenPitches = InstrumentSettings.defaultOpenPitches
    @AppStorage(InstrumentSettings.Key.capo) private var storedCapo = InstrumentSettings.defaultCapo

    var body: some View {
        Group {
            if audioInput.permission == .denied {
                MicrophoneAccessDeniedView()
            } else {
                drill
            }
        }
        .navigationTitle("Note → play it")
        .navigationSubtitle(model.windowSubtitle)
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                DrillOptionsBar(model: model).disabled(model.isRunning)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                DrillRunButtons(model: model)
            }
        }
        .listensToAudioInput(model.audioConsumer)
        .onDisappear { model.leave() }
        .onChange(of: storedOpenPitches, initial: true) {
            model.tuning = InstrumentSettings.tuning(from: storedOpenPitches)
        }
        .onChange(of: storedCapo, initial: true) {
            model.capo = InstrumentSettings.capo(from: storedCapo)
        }
        .onChange(of: model.isRunning) {
            if !model.isRunning, !model.snapshot.attempts.isEmpty { showSummary = true }
        }
        .sheet(isPresented: $showSummary) {
            VStack(alignment: .trailing, spacing: 16) {
                DrillRunSummary(model: model)
                Button("Done") { showSummary = false }.keyboardShortcut(.defaultAction)
            }
            .padding(24)
            .frame(width: 520)
        }
    }

    private var drill: some View {
        VStack(spacing: 0) {
            FretboardView(diagram: model.diagram)
                .frame(height: 210)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
                .padding(.horizontal, 24)
                .padding(.top, 20)

            Spacer(minLength: 12)
            HStack(spacing: 24) {
                DrillFlashcard(model: model)
                DrillCountdownRing(model: model).frame(width: 64, height: 64)
            }
            DrillFeedback(model: model).padding(.top, 10)
            DrillAttemptStrip(model: model).padding(.top, 10)
            Spacer(minLength: 12)

            Divider()
            HStack(spacing: 18) {
                Text("\(model.stats.prompts) prompts")
                Text("first-try \(model.stats.firstTryText)")
                Text("median \(model.stats.medianText)")
                Spacer()
                AudioInputFallbackNotice()
                AudioInputLine()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .frame(height: 32)
            .background(.bar)
        }
    }
}

// MARK: - Toolbar

/// Notes, Frets, Strings and Order. Locked (disabled) while a run goes.
private struct DrillOptionsBar: View {
    @Bindable var model: DrillViewModel

    var body: some View {
        Picker("Notes", selection: $model.options.notes) {
            Text("Naturals").tag(NotePlayItOptions.Notes.naturals)
            Text("All notes").tag(NotePlayItOptions.Notes.all)
        }
        .help("Notes (an In order check walks every note)")
        .disabled(model.options.order == .inOrder)
        Picker("Frets", selection: $model.options.frets) {
            ForEach(NotePlayItOptions.fretRanges, id: \.self) { range in
                Text("\(range.lowerBound)–\(range.upperBound)").tag(range)
            }
        }
        .help("Frets")
        Menu(stringsTitle) {
            ForEach(model.tuning.strings, id: \.self) { string in
                Toggle(isOn: included(string)) {
                    Text(model.tuning.stringLabel(ofString: string).capitalizedFirst)
                }
            }
        }
        .help("Strings")
        Picker("Order", selection: $model.options.order) {
            Text("Random").tag(NotePlayItOptions.Order.random)
            Text("In order (check)").tag(NotePlayItOptions.Order.inOrder)
        }
        .help("Order")
    }

    /// "Strings: all", or the included string numbers, "Strings: 6 5".
    private var stringsTitle: String {
        guard let strings = model.options.strings, strings.count < model.tuning.stringCount else { return "Strings: all" }
        return "Strings: " + strings.sorted().map { "\(model.tuning.stringNumber(ofString: $0))" }.joined(separator: " ")
    }

    /// Whether a string is included; at least one string always stays in.
    private func included(_ string: Int) -> Binding<Bool> {
        let all = Set(model.tuning.strings)
        return Binding(
            get: { model.options.strings?.contains(string) ?? true },
            set: { isOn in
                var strings = model.options.strings ?? all
                if isOn { strings.insert(string) } else if strings.count > 1 { strings.remove(string) }
                model.options.strings = strings == all ? nil : strings
            })
    }
}

/// Start (↩) when idle; Pause/Resume (P) and Stop (Esc) during a run.
private struct DrillRunButtons: View {
    let model: DrillViewModel

    var body: some View {
        if model.isRunning {
            Button(model.isPaused ? "Resume" : "Pause") { model.togglePause() }
                .keyboardShortcut("p", modifiers: [])
            Button("Stop") { model.stop() }
                .keyboardShortcut(.escape, modifiers: [])
        } else {
            Button("Start") { model.start() }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Under the neck

/// The prompt, large: "F♯" over "on string 3 (G)", tinted red / green / orange for wrong / right / timeout.
private struct DrillFlashcard: View {
    let model: DrillViewModel

    var body: some View {
        VStack(spacing: 4) {
            if model.isRunning, let prompt = model.snapshot.prompt {
                Text(prompt.noteName).font(.system(size: 76, weight: .bold, design: .rounded))
                Text(model.promptStringText).font(.title2).foregroundStyle(.secondary)
            } else {
                Text("Note → play it").font(.title.weight(.semibold))
                Text("Press Start (↩)").font(.title3).foregroundStyle(.secondary)
            }
        }
        .frame(width: 320, height: 150)
        .background(RoundedRectangle(cornerRadius: 18).fill(tint))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(nsColor: .separatorColor)))
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch model.snapshot.phase {
        case .correct: .green.opacity(0.15)
        case .wrong: .red.opacity(0.12)
        case .timedOut: .orange.opacity(0.15)
        default: Color(nsColor: .controlBackgroundColor)
        }
    }
}

/// The 10 s timeout: a ring that empties as time runs out (orange in the last 30%), with the seconds so far.
private struct DrillCountdownRing: View {
    let model: DrillViewModel

    var body: some View {
        let countdown = model.countdown
        let fraction = countdown?.fraction ?? 0
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0, to: 1 - fraction)
                .stroke(fraction > 0.7 ? Color.orange : Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(countdown.map { String(format: "%.1f", $0.elapsed) } ?? "")
                .font(.callout.monospacedDigit())
        }
        .accessibilityElement()
        .accessibilityLabel("Time")
        .accessibilityValue(countdown.map { Text("\(Int($0.elapsed)) seconds") } ?? Text("Not running"))
    }
}

/// "You played G", "Fret 7 · 0.82 s", "Time's up — here it is", "Paused" or "Listening…".
private struct DrillFeedback: View {
    let model: DrillViewModel

    var body: some View {
        Group {
            switch model.snapshot.phase {
            case .wrong(let played):
                Label("You played \(played.sharpName)", systemImage: "xmark.circle.fill").foregroundStyle(.red)
            case .correct:
                Label(model.snapshot.attempts.last?.rightAnswerText ?? "", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .timedOut:
                Label("Time's up — here it is", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange)
            case .paused:
                Label("Paused", systemImage: "pause.circle").foregroundStyle(.secondary)
            case .waiting:
                Label("Listening…", systemImage: "waveform").foregroundStyle(.secondary)
            case .idle:
                Text(" ")
            }
        }
        .font(.title2.weight(.medium))
    }
}

/// The last ~14 attempts: note and time, green right first time, orange timed out, red otherwise.
private struct DrillAttemptStrip: View {
    let model: DrillViewModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(model.recentAttempts, id: \.id) { item in
                let attempt = item.attempt
                VStack(spacing: 0) {
                    Text(attempt.prompt.noteName).font(.caption.weight(.semibold))
                    Text(attempt.shortTimeText).font(.caption2.monospacedDigit())
                }
                .frame(width: 38, height: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill(color(attempt).opacity(0.2)))
                .help(attempt.summaryLine(in: model.tuning))
            }
        }
        .frame(height: 34)
    }

    private func color(_ attempt: Attempt) -> Color {
        attempt.firstRight ? .green : attempt.timedOut ? .orange : .red
    }
}

// MARK: - Summary

/// The run summary on Stop: prompts, first-try accuracy, median, timeouts and the slowest prompts with the wrong
/// notes played first. An "In order (check)" run lists its misses and its slowest onsets instead.
private struct DrillRunSummary: View {
    let model: DrillViewModel

    var body: some View {
        let stats = model.stats
        VStack(alignment: .leading, spacing: 10) {
            Text(model.isCheckRun ? "Check run" : "Run summary").font(.headline)
            HStack(spacing: 28) {
                stat("Prompts", "\(stats.prompts)")
                stat("First-try right", stats.firstTryText)
                stat("Median time", stats.medianText)
                stat("Timed out", "\(stats.timeouts)")
            }
            if model.isCheckRun {
                list("Misses", stats.misses, emptyText: "None: every location was right first time.")
                list("Slowest onsets", stats.slowest(5).filter { !$0.timedOut })
            } else {
                list("Slowest", stats.slowest(3))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.monospacedDigit().weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func list(_ title: String, _ attempts: [Attempt], emptyText: String? = nil) -> some View {
        if !attempts.isEmpty || emptyText != nil {
            Text(title).font(.subheadline.weight(.semibold)).padding(.top, 4)
            if attempts.isEmpty, let emptyText {
                Text(emptyText).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(attempts.enumerated()), id: \.offset) { _, attempt in
                Text(line(attempt)).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// Check runs name the fret that was checked.
    private func line(_ attempt: Attempt) -> String {
        let line = attempt.summaryLine(in: model.tuning)
        guard model.isCheckRun, let target = attempt.prompt.target else { return line }
        return "Fret \(target.fret): \(line)"
    }
}

private extension String {
    /// "String 3 (G)" from "string 3 (G)".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

#Preview {
    DrillView()
        .environment(AudioInputService())
        .frame(width: 1100, height: 600)
}
