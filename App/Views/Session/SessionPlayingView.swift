import PracticeCore
import SwiftUI
import TheoryCore

/// A session that is going: the drills bar stays on top through Ready cards, drills and pauses, so nothing
/// jumps.
struct SessionPlayingView: View {
    let model: SessionViewModel
    /// Why it can't resume; nil when it can.
    let inputProblem: SessionProblem?
    let resume: () -> Void

    var body: some View {
        let snapshot = model.snapshot
        let block = snapshot.blocks[snapshot.blockIndex]
        VStack(spacing: 0) {
            SessionDrillsBar(blocks: snapshot.blocks, current: snapshot.blockIndex)
            Divider()
            if snapshot.stage == .ready {
                Spacer(minLength: 8)
                SessionReadyCard(kind: block.kind, length: block.timeText, seconds: snapshot.readySeconds)
                Spacer(minLength: 8)
            } else if snapshot.stage == .paused {
                Spacer(minLength: 8)
                SessionPausedCard(model: model, inputProblem: inputProblem, resume: resume)
                Spacer(minLength: 8)
            } else {
                DrillNeck(display: snapshot.display, fretboard: model.fretboard, height: 190)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                Spacer(minLength: 8)
                if let display = snapshot.display { SessionTarget(model: model, display: display) }
                Spacer(minLength: 8)
            }
            Divider()
            HStack(spacing: 14) {
                if snapshot.stage != .paused { SessionKey(key: "Space", action: spaceAction) }
                if snapshot.stage == .playing {
                    SessionKey(key: "S", action: "skip")
                    if let repeatTitle = block.kind.repeatTitle { SessionKey(key: "R", action: repeatTitle.lowercased()) }
                }
                if snapshot.stage == .paused {
                    if inputProblem == nil { SessionKey(key: "P", action: "resume") }
                    if model.asksToEnd { SessionKey(key: "↩", action: "end session") }
                    SessionKey(key: "Esc", action: model.asksToEnd ? "stay paused" : "end")
                } else {
                    SessionKey(key: "P", action: "pause")
                    SessionKey(key: "Esc", action: "end")
                }
                Spacer()
                AttemptLogNotice()
                AudioInputFallbackNotice()
                AudioInputLine()
            }
            .sessionStatusBar()
        }
    }

    private var spaceAction: String {
        if model.stage == .ready { return "start" }
        return model.snapshot.blockIndex + 1 < model.snapshot.blocks.count ? "next block" : "finish"
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

/// One column per block: its drill, its time left (or spent, once over) and how far through it is.
private struct SessionDrillsBar: View {
    let blocks: [SessionViewModel.BlockProgress]
    let current: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(block.kind.title, systemImage: block.kind.symbol).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(block.timeText).monospacedDigit()
                    }
                    .font(.caption.weight(index == current ? .semibold : .regular))
                    GeometryReader { geo in
                        Capsule().fill(.secondary.opacity(0.2))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.accentColor).frame(width: geo.size.width * block.fraction)
                            }
                    }
                    .frame(height: 6)
                }
                .opacity(index == current ? 1 : 0.6)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(index == current ? .isSelected : [])
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }
}

private struct SessionReadyCard: View {
    let kind: DrillKind
    let length: String
    let seconds: Int

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: kind.symbol).font(.system(size: 64)).foregroundStyle(.tint)
            Text(kind.title).font(.system(size: 56, weight: .bold, design: .rounded))
            Text(kind.instructions).font(.title2).foregroundStyle(.secondary)
            Text("\(seconds)").font(.system(size: 72, weight: .heavy, design: .rounded)).monospacedDigit()
            Text("\(length) · Space to start now").foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
}

/// Paused, and after Esc the question whether to end.
private struct SessionPausedCard: View {
    let model: SessionViewModel
    let inputProblem: SessionProblem?
    let resume: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(model.asksToEnd ? "End session?" : "Paused").font(.system(size: 72, weight: .bold, design: .rounded))
            if let notice = model.pauseNotice { Text(notice).font(.title2).foregroundStyle(.secondary) }
            HStack {
                if model.asksToEnd {
                    Button("End session ↩", action: model.end)
                    Button("Stay paused (Esc)", action: model.cancelEnd)
                } else {
                    Button("Resume (P)", action: resume).disabled(inputProblem != nil)
                    Button("End session", action: model.end)
                }
            }
            .controlSize(.large)
            if let inputProblem { SessionProblemNotice(problem: inputProblem) }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
}
