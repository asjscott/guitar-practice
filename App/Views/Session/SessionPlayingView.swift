import PracticeCore
import SwiftUI
import TheoryCore

/// A session that is going: the drills bar stays on top through Ready cards, drills and pauses, so nothing
/// jumps. In scale, triad and progression blocks it is at the bottom, so that the neck gets the top.
struct SessionPlayingView: View {
    @Bindable var model: SessionViewModel

    private var kind: DrillKind { model.snapshot.blocks[model.snapshot.blockIndex].kind }

    private var isBarOnTop: Bool { kind.module == .notes }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if isBarOnTop {
                    drillsBar
                    Divider()
                }
                content
                if !isBarOnTop {
                    Divider()
                    drillsBar
                }
            }
            .disabled(model.isPanelOpen)
            .metronomePanel(isOpen: $model.isPanelOpen, isAvailable: kind.hasPasses, settings: passSettings,
                            alignment: .bottomTrailing)
            Divider()
            ViewThatFits(in: .horizontal) {
                statusBar(theme: model.theme?.text)
                statusBar(theme: nil)       // in a narrow window
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

    private var drillsBar: some View {
        SessionDrillsBar(blocks: model.snapshot.blocks, current: model.snapshot.blockIndex, finish: model.snapshot.finish)
    }

    @ViewBuilder private var content: some View {
        let snapshot = model.snapshot
        if snapshot.stage == .ready {
            Spacer(minLength: 8)
            SessionReadyCard(kind: kind, length: snapshot.blocks[snapshot.blockIndex].timeText, seconds: snapshot.readySeconds,
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
        switch kind.module {
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
            SessionKey(key: "S", action: "skip")
            SessionKey(key: "+", action: "2 min")
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
        return model.snapshot.blockIndex + 1 < model.snapshot.blocks.count ? "next block" : "finish"
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

/// One column per block: its drill, its time left (or over, or spent) and how far through it is. Then when
/// the session will end.
private struct SessionDrillsBar: View {
    let blocks: [SessionViewModel.BlockProgress]
    let current: Int
    let finish: SessionViewModel.Finish

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(block.kind.title, systemImage: block.kind.symbol).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(block.timeText).monospacedDigit()
                            .foregroundStyle(block.isOvertime ? .orange : .primary)
                    }
                    .font(.caption.weight(index == current ? .semibold : .regular))
                    GeometryReader { geo in
                        Capsule().fill(.secondary.opacity(0.2))
                            .overlay(alignment: .leading) {
                                Capsule().fill(block.isOvertime ? Color.orange : .accentColor).frame(width: geo.size.width * block.fraction)
                            }
                    }
                    .frame(height: 6)
                }
                .opacity(index == current ? 1 : 0.6)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(index == current ? .isSelected : [])
            }
            finishText.font(.caption).foregroundStyle(.secondary).monospacedDigit().padding(.leading, 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    /// Later and later while paused.
    @ViewBuilder private var finishText: some View {
        if let afterResuming = finish.afterResuming {
            TimelineView(.periodic(from: .now, by: 1)) { Text(sessionFinishText(afterResuming, after: $0.date)) }
        } else {
            Text(finish.timeText)
        }
    }
}

private struct SessionReadyCard: View {
    let kind: DrillKind
    let length: String
    let seconds: Int
    /// How the backing will be heard, in a progression block.
    var notices: [String] = []

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: kind.symbol).font(.system(size: 64)).foregroundStyle(.tint)
            Text(kind.title).font(.system(size: 56, weight: .bold, design: .rounded))
            Text(kind.instructions).font(.title2).foregroundStyle(.secondary)
            Text("\(seconds)").font(.system(size: 72, weight: .heavy, design: .rounded)).monospacedDigit()
            Text("\(length) · Space to start now").foregroundStyle(.secondary)
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
