import PracticeCore
import SwiftUI
import TheoryCore

/// A session that is going, layout C: the rail down the left through Ready cards, drills and pauses, so nothing jumps;
/// the drill beside it.
struct SessionPlayingView: View {
    @Bindable var model: SessionViewModel

    private var step: RailStep { model.snapshot.steps[model.snapshot.blockIndex] }
    private var kind: DrillKind { step.kind }

    var body: some View {
        HStack(spacing: 0) {
            SessionRail(title: "Session · \(model.snapshot.elapsedText)", steps: model.snapshot.steps)
            Divider()
            VStack(spacing: 0) {
                VStack(spacing: 0) { content }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .disabled(model.isPanelOpen)
                    .metronomePanel(isOpen: $model.isPanelOpen, isAvailable: kind.hasPasses, settings: passSettings,
                                    alignment: .bottomTrailing)
                Divider()
                ViewThatFits(in: .horizontal) {
                    statusBar(theme: model.theme?.text)
                    statusBar(theme: nil)       // in a narrow window
                }
            }
        }
        .overlay { SessionFlash(chime: model.flash) }
    }

    private func statusBar(theme: String?) -> some View {
        HStack(spacing: 14) {
            if model.isPanelOpen {
                SessionKey(key: "Esc", action: "close")
            } else {
                keys(of: model.stage)
            }
            Spacer(minLength: 0)
            if let theme { Text(theme) }
            if kind.hasPasses { MetronomeButton(settings: passSettings.wrappedValue, isOpen: $model.isPanelOpen) }
            if model.noSoundNotice != nil {
                Label("No sound", systemImage: "speaker.slash.fill").foregroundStyle(.orange)
                    .help("Chimes flash.")
            }
            AttemptLogNotice()
            AudioInputFallbackNotice()
            AudioInputLine()
        }
        .lineLimit(1)
        .sessionStatusBar()
    }

    @ViewBuilder private var content: some View {
        let snapshot = model.snapshot
        if snapshot.stage == .ready {
            Spacer(minLength: 8)
            SessionReadyCard(kind: kind, detail: step.detail, seconds: snapshot.readySeconds,
                             notices: kind.hasBacking ? model.backingNotices : [])
            Spacer(minLength: 8)
        } else if snapshot.stage == .paused {
            Spacer(minLength: 8)
            SessionPausedCard(model: model)
            Spacer(minLength: 8)
        } else {
            drill(snapshot.display)
        }
    }

    @ViewBuilder private func drill(_ display: DrillDisplay?) -> some View {
        let now = Duration.seconds(model.now)
        switch kind.module {
        case .notes where kind.goesRoundTheCircle:
            NoteCirclePrompt(display: display, fretboard: model.fretboard, now: now) {}
                .padding(.top, 8)
        case .scales where kind.goesRoundTheCircle:
            ScaleCirclePrompt(display: display, position: model.theme?.theme.position(on: model.fretboard),
                              restingMarkers: [], fretboard: model.fretboard, now: now) {}
        case .triads where kind.goesRoundTheCircle:
            TriadCirclePrompt(display: display, frets: model.frets, fretboard: model.fretboard, now: now) {}
        case .notes:
            DrillNeck(display: display, fretboard: model.fretboard, height: 190)
                .padding(.horizontal, 24)
                .padding(.top, 14)
            Spacer(minLength: 8)
            if let display { SessionTarget(model: model, display: display) }
            Spacer(minLength: 8)
        case .scales:
            PassPrompt(display: display, position: nil, restingMarkers: [], settings: passSettings.wrappedValue,
                       fretboard: model.fretboard) {}
        case .triads:
            TriadPrompt(display: display, hasClimbs: kind.hasClimbs, frets: model.frets, fretboard: model.fretboard) {
                LiveCountdownRing { model.countdown }
            } resting: {
                EmptyView()
            }
        case .progressions:
            ProgressionPrompt(display: display, position: model.theme?.theme.position(on: model.fretboard),
                              fretboard: model.fretboard) {}
        }
    }

    @ViewBuilder private func keys(of stage: SessionStage) -> some View {
        if stage != .paused { SessionKey(key: "Space", action: spaceAction) }
        if stage == .playing {
            if !kind.hasNoPrompts { SessionKey(key: "S", action: "skip") }
            if model.hasPlannedLength { SessionKey(key: "+", action: "2 min") }
            if kind.fades { SessionKey(key: "H", action: "show") }
            if let repeatTitle = kind.repeatTitle { SessionKey(key: "R", action: repeatTitle.lowercased()) }
        }
        if stage == .paused {
            if model.inputProblem == nil { SessionKey(key: "P", action: "resume") }
            if model.asksToEnd { SessionKey(key: "↩", action: "end session") }
            SessionKey(key: "Esc", action: model.asksToEnd ? "stay paused" : "end")
        } else {
            SessionKey(key: "P", action: "pause")
            SessionKey(key: "Esc", action: "end")
        }
    }

    /// Of a scale block.
    private var passSettings: Binding<PassSettings> {
        Binding(get: { model.passSettings ?? PassSettings() }, set: { model.passSettings = $0 })
    }

    private var spaceAction: String {
        if model.stage == .ready { return "start" }
        let isLast = !model.snapshot.steps.indices.contains { $0 > model.snapshot.blockIndex && model.snapshot.steps[$0].state == .toCome }
        return isLast ? "finish" : "next step"
    }
}

/// A chime to see: the whole screen lights up and fades, less for the softer one.
private struct SessionFlash: View {
    let chime: AppSound?

    var body: some View {
        Color.orange
            .opacity(chime == nil ? 0 : chime == .softChime ? 0.2 : 0.4)
            .animation(.easeOut(duration: 0.3), value: chime)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Apart, so that only it is redrawn on every tick.
private struct SessionTarget: View {
    let model: SessionViewModel
    let display: DrillDisplay

    var body: some View { DrillTarget(display: display, countdown: model.countdown, typed: model.nameEntry.text) }
}

private struct SessionKey: View {
    let key: String
    let action: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .fontWeight(.semibold)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.18)))
            Text(action)
        }
    }
}

private struct SessionReadyCard: View {
    let kind: DrillKind
    /// What the step does today.
    let detail: String
    let seconds: Int
    /// How the backing will be heard, in a progression block.
    var notices: [String] = []

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: kind.symbol).font(.system(size: 64)).foregroundStyle(.tint)
            Text(kind.title).font(.system(size: 56, weight: .bold, design: .rounded))
            Text(kind.instructions).font(.title2).foregroundStyle(.secondary)
            Text("\(seconds)").font(.system(size: 72, weight: .heavy, design: .rounded)).monospacedDigit()
            Text(detail).font(.title3)
            Text("Space to start now").foregroundStyle(.secondary)
            ForEach(notices, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
}

/// Paused, and after Esc the question whether to end.
private struct SessionPausedCard: View {
    let model: SessionViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text(model.asksToEnd ? "End session?" : "Paused").font(.system(size: 72, weight: .bold, design: .rounded))
            if let notice = model.pauseNotice { Text(notice).font(.title2).foregroundStyle(.secondary) }
            HStack {
                if model.asksToEnd {
                    Button("End session ↩", action: model.end)
                    Button("Stay paused (Esc)", action: model.cancelEnd)
                } else {
                    Button("Resume (P)", action: model.resume).disabled(model.inputProblem != nil)
                    Button("End session", action: model.end)
                }
            }
            .controlSize(.large)
            if let problem = model.inputProblem { AudioInputProblemNotice(problem: problem) }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
}
