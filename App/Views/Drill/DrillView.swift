import PracticeCore
import SwiftUI
import TheoryCore

/// The Drill screen (free practice), D4 (or P4 for scales and triads): a drill picker and options in the toolbar with Start (↩), Pause/Resume (P),
/// Skip (S) and Stop (Esc), plus Repeat (R) where the drill has one; the neck card with the target string lit; under
/// it the target card with its countdown ring, a feedback line and a strip of recent attempts; a status bar with
/// running stats and the input meter; a summary sheet on Stop. A listening screen: audio input runs while it is
/// open. Leaving it pauses the run, as do sleep and losing the input. Follows the tuning, capo, position system,
/// time signature and emphasis in Settings.
struct DrillView: View {
    @Bindable var model: DrillViewModel
    @State private var showSummary = false
    @Environment(AudioInputService.self) private var audioInput
    @Environment(AppSoundOutput.self) private var soundOutput
    @Environment(AttemptLog.self) private var log
    @Environment(Metronome.self) private var metronome
    @AppStorage(InstrumentSettings.Key.positionSystem) private var positionSystem = InstrumentSettings.defaultPositionSystem
    private let meters = StoredMeters()

    var body: some View {
        Group {
            if audioInput.permission == .denied {
                MicrophoneAccessDeniedView()
            } else {
                drill
            }
        }
        .navigationTitle(model.kind.title)
        .navigationSubtitle(model.windowSubtitle)
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                DrillOptionsBar(model: model).disabled(model.isRunning)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.kind.usesMetronome { MetronomeButton(settings: model.passSettings, isOpen: $model.isPanelOpen) }
                DrillRunButtons(model: model).disabled(model.isPanelOpen)
            }
        }
        .typesNoteNames(isActive: model.takesNoteNames) { model.press($0) }
        .holdsHint(isActive: model.takesHint) { model.hint(isShown: $0) }
        .listensToAudioInput(model.audioConsumer)
        .noticesInterruptions(input: model.inputChanged, sleep: model.pause(notice:))
        .onAppear {
            model.log = log
            model.soundOutput = soundOutput
            model.metronome = metronome
        }
        .onChange(of: soundOutput.problem) { model.soundProblemChanged() }
        .onDisappear { model.leave() }
        .followsInstrumentSettings { tuning, capo in
            model.tuning = tuning
            model.capo = capo
        }
        .onChange(of: positionSystem, initial: true) { model.positionSystem = positionSystem }
        .onChange(of: meters.meter, initial: true) { model.passSettings.meter = meters.meter }
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
            switch model.kind.module {
            case .notes: notes
            case .scales: scales
            case .triads: triads
            }
            Divider()
            HStack(spacing: 18) {
                if model.kind.usesMetronome {
                    Text("\(model.completePasses) \(model.completePasses == 1 ? "pass" : "passes")")
                    Text("\(model.cleanPasses) clean")
                } else {
                    Text("\(model.stats.prompts) \(model.stats.prompts == 1 ? "prompt" : "prompts")")
                    Text("first-try \(model.stats.firstTryText)")
                    Text("median \(model.stats.medianText)")
                }
                if model.stats.skips > 0 { Text("\(model.stats.skips) skipped") }
                Spacer()
                AttemptLogNotice()
                AudioInputFallbackNotice()
                AudioInputLine()
            }
            .sessionStatusBar()
        }
        .metronomePanel(isOpen: $model.isPanelOpen, isAvailable: model.kind.usesMetronome, settings: $model.passSettings)
    }

    @ViewBuilder private var notes: some View {
        DrillNeck(display: model.snapshot.display, fretboard: model.fretboard)
            .padding(.horizontal, 24)
            .padding(.top, 20)
        Spacer(minLength: 12)
        if let display = model.snapshot.display {
            DrillTarget(display: display, countdown: model.countdown, typed: model.nameEntry.text)
        } else {
            DrillRestingCard(model: model)
        }
        DrillAttemptStrip(model: model).padding(.top, 10)
        Spacer(minLength: 12)
    }

    private var scales: some View {
        PassPrompt(display: model.snapshot.display, position: model.position, restingMarkers: model.restingMarkers,
                   settings: model.passSettings, fretboard: model.fretboard) {
            DrillRestingText(model: model)
        }
    }

    private var triads: some View {
        TriadPrompt(display: model.snapshot.display, hasClimbs: model.kind == .inversions, frets: model.options.frets, fretboard: model.fretboard) {
            TriadCountdown(model: model)
        } resting: {
            DrillRestingText(model: model)
        }
    }
}

/// Apart, so that only it is redrawn on every tick.
private struct TriadCountdown: View {
    let model: DrillViewModel

    var body: some View { DrillCountdownRing(countdown: model.countdown) }
}

/// Warns that attempts aren't being saved; otherwise nothing.
struct AttemptLogNotice: View {
    @Environment(AttemptLog.self) private var log

    var body: some View {
        if let problem = log.problem {
            Label {
                Text("Practice isn’t being saved")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
            .help(problem)
        }
    }
}

// MARK: - Toolbar

/// The drill, then the options that apply to its module. Locked (disabled) while a run goes.
private struct DrillOptionsBar: View {
    @Bindable var model: DrillViewModel

    var body: some View {
        DrillPicker(kind: $model.kind)
        switch model.kind.module {
        case .notes: NoteOptions(model: model)
        // Gone during a run, when the header names them: its buttons need the room.
        case .scales: if !model.isRunning { ScaleOptions(setup: model.setup, options: $model.options) }
        case .triads: TriadOptions(kind: model.kind, options: $model.options)
        }
    }
}

/// Notes, Frets, Strings and (where the drill offers it) Order.
private struct NoteOptions: View {
    @Bindable var model: DrillViewModel

    var body: some View {
        Picker("Notes", selection: $model.options.notes) {
            Text("Naturals").tag(DrillOptions.Notes.naturals)
            Text("All notes").tag(DrillOptions.Notes.all)
        }
        .help("Notes (an In order check walks every note)")
        .disabled(model.isSetToCheck)
        FretsPicker(frets: $model.options.frets)
        Menu(stringsTitle) {
            ForEach(model.tuning.strings, id: \.self) { string in
                Toggle(isOn: included(string)) {
                    Text(model.tuning.stringLabel(ofString: string).capitalizedFirst)
                }
            }
        }
        .help("Strings")
        if model.kind.offersOrder {
            Picker("Order", selection: $model.options.order) {
                Text("Random").tag(DrillOptions.Order.random)
                Text("In order (check)").tag(DrillOptions.Order.inOrder)
            }
            .help("Order")
        }
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

struct FretsPicker: View {
    @Binding var frets: ClosedRange<Int>

    var body: some View {
        Picker("Frets", selection: $frets) {
            ForEach(DrillOptions.fretRanges, id: \.self) { range in
                Text("\(range.lowerBound)–\(range.upperBound)").tag(range)
            }
        }
        .help("Frets")
    }
}

/// Drills by module.
struct DrillPicker: View {
    @Binding var kind: DrillKind
    var kinds = DrillKind.all

    var body: some View {
        Picker("Drill", selection: $kind) {
            ForEach(DrillModule.groups(of: kinds, by: \.module), id: \.module) { group in
                Section(group.module.title) {
                    ForEach(group.members) { Text($0.title).tag($0) }
                }
            }
        }
        .help("Drill")
    }
}

/// Start (↩) when idle; Pause/Resume (P), Skip (S), Repeat (R) and Stop (Esc) during a run. Start (and ↩) is
/// disabled until microphone access is given, while there's no input device (or no output, for a drill that needs sound), or
/// nothing can be prompted.
private struct DrillRunButtons: View {
    let model: DrillViewModel

    var body: some View {
        if model.isRunning {
            Button(model.isPaused ? "Resume" : "Pause") { model.togglePause() }
                .keyboardShortcut("p", modifiers: [])
                .disabled(model.isPaused && model.inputProblem != nil)
            Button("Skip") { model.skip() }
                .keyboardShortcut("s", modifiers: [])
                .disabled(model.isPaused)
            if let repeatTitle = model.kind.repeatTitle {
                Button(repeatTitle) { model.repeatPrompt() }
                    .keyboardShortcut("r", modifiers: [])
                    .disabled(model.isPaused)
            }
            Button("Stop") { model.stop() }
                .keyboardShortcut(.escape, modifiers: [])
        } else {
            Button("Start") { model.start() }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(model.startProblem != nil)
                .help(model.startProblem ?? model.soundProblem ?? "Start")
        }
    }
}

// MARK: - Under the neck

/// In place of a prompt: the drill and how to start (or why it can't), or Paused.
private struct DrillRestingCard: View {
    let model: DrillViewModel

    var body: some View {
        // The same layout as DrillTarget, so nothing jumps.
        VStack(spacing: 10) {
            HStack(spacing: 24) {
                DrillTargetCard { DrillRestingText(model: model) }
                DrillCountdownRing(countdown: nil).frame(width: 64, height: 64)
            }
            Text(" ").font(.title2.weight(.medium))
        }
    }
}

/// The drill and how to start (or why it can't), or Paused.
private struct DrillRestingText: View {
    let model: DrillViewModel

    var body: some View {
        if model.isPaused {
            Label("Paused", systemImage: "pause.circle").font(.title.weight(.semibold))
            if let reason = model.inputProblem?.text ?? model.soundProblem ?? model.pauseNotice {
                Text(reason).font(.title3).foregroundStyle(.orange)
            } else {
                Text(resumeText).font(.title3).foregroundStyle(.secondary)
            }
        } else {
            Text(model.kind.title).font(.title.weight(.semibold))
            if let reason = model.startProblem ?? model.soundProblem {
                Text(reason).font(.title3).foregroundStyle(.orange)
            } else {
                Text("Press Start (↩)").font(.title3).foregroundStyle(.secondary)
                if model.kind.usesMetronome {
                    Text(model.kind.instructions + " Hold H to see the position: the pass then isn’t clean.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var resumeText: String {
        if model.kind.usesMetronome { return model.resumesSamePrompt ? "Resume (P) to restart the pass" : "Resume (P) for the next pass" }
        return model.resumesSamePrompt ? "Resume (P) to carry on" : "Resume (P) for a new prompt"
    }
}

/// The last ~14 attempts: note and time, green right first time, orange timed out, grey skipped, red otherwise.
private struct DrillAttemptStrip: View {
    let model: DrillViewModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(model.recentAttempts, id: \.id) { item in
                let attempt = item.attempt
                VStack(spacing: 0) {
                    Text(hidesNote(attempt) ? "–" : attempt.prompt.noteName).font(.caption.weight(.semibold))
                    Text(attempt.shortTimeText).font(.caption2.monospacedDigit())
                }
                .frame(width: 38, height: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill(color(attempt).opacity(0.2)))
                .help(hidesNote(attempt) ? "Skipped" : attempt.summaryLine(in: model.tuning))
            }
        }
        .frame(height: 34)
    }

    /// A skip reveals nothing.
    private func hidesNote(_ attempt: Attempt) -> Bool { attempt.skipped && model.kind.hidesNote }

    private func color(_ attempt: Attempt) -> Color {
        switch attempt.outcome {
        case .answered: attempt.firstRight ? .green : .red
        case .timedOut: .orange
        case .skipped: .gray
        }
    }
}

// MARK: - Summary

/// The run summary on Stop: prompts, first-try accuracy, median, timeouts, skips and the slowest prompts with the wrong
/// notes played first. An "In order (check)" run lists its misses and its slowest onsets instead.
private struct DrillRunSummary: View {
    let model: DrillViewModel

    var body: some View {
        let stats = model.stats
        VStack(alignment: .leading, spacing: 10) {
            Text(model.isCheckRun ? "Check run" : "Run summary").font(.headline)
            HStack(spacing: 28) {
                if model.kind.usesMetronome {
                    stat("Passes", "\(model.completePasses)")
                    stat("Clean", "\(model.cleanPasses)")
                } else {
                    stat("Prompts", "\(stats.prompts)")
                    stat("First-try right", stats.firstTryText)
                    stat("Median time", stats.medianText)
                }
                stat("Timed out", "\(stats.timeouts)")
                stat("Skipped", "\(stats.skips)")
            }
            if model.isCheckRun {
                list("Misses", stats.misses, emptyText: "None: every location was right first time.")
                list("Slowest onsets", stats.slowest(5).filter { $0.outcome == .answered })
            } else if !model.kind.usesMetronome {
                list("Slowest", stats.slowest(3))
                if !model.sweeps.isEmpty { lines("Sweeps", model.sweeps.suffix(6).map(\.summaryLine)) }
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

    @ViewBuilder
    private func lines(_ title: String, _ lines: [String]) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).padding(.top, 4)
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            Text(line).font(.callout).foregroundStyle(.secondary)
        }
    }

    /// Check runs name the fret that was checked.
    private func line(_ attempt: Attempt) -> String {
        let line = attempt.summaryLine(in: model.tuning, key: model.key)
        guard model.isCheckRun, let target = attempt.prompt.target else { return line }
        return "Fret \(target.fret): \(line)"
    }
}

#Preview {
    DrillView(model: DrillViewModel())
        .environment(AudioInputService())
        .environment(AppSoundOutput(isInert: true))
        .environment(Metronome(output: AppSoundOutput(isInert: true)))
        .environment(AttemptLog.inMemory())
        .frame(width: 1100, height: 600)
}
