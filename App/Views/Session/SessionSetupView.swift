import PracticeCore
import SwiftUI

/// Why a session can't start.
enum SessionProblem: Equatable {
    case input(AudioInputProblem)
    case nothingToPrompt(String)
}

/// Before a session: the theme, minutes, difficulty, the blocks they give, and Start (↩).
struct SessionSetupView: View {
    @Binding var minutes: Int
    @Binding var naturalsOnly: Bool
    @Binding var range: SessionRange
    /// Nil until it is known.
    let theme: SessionTheme?
    /// Nil once it can't be rerolled.
    let reroll: (() -> Void)?
    let blocks: [SessionBlock]
    let problem: SessionProblem?
    /// Nil with sound.
    var noSoundNotice: String?
    let start: () -> Void

    /// What is stored could be anything.
    private var shownMinutes: Int { SessionSetup(minutes: minutes).minutes }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            choices
            Spacer(minLength: 8)
            Divider()
            HStack(spacing: 14) {
                Spacer()
                AttemptLogNotice()
                AudioInputFallbackNotice()
                AudioInputLine()
            }
            .sessionStatusBar()
        }
    }

    private var choices: some View {
        VStack(spacing: 22) {
            VStack(spacing: 4) {
                Text(theme?.key.description ?? " ").font(.system(size: 64, weight: .bold, design: .rounded))
                HStack {
                    Text(theme?.positionName ?? "").foregroundStyle(.secondary)
                    if let reroll { Button("Reroll", action: reroll) }
                }
                .font(.title3)
                .frame(minHeight: 28)
            }
            HStack(spacing: 20) {
                step("minus.circle", "Less time", by: -SessionSetup.minutesStep)
                Text("\(shownMinutes) min")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 190)
                step("plus.circle", "More time", by: SessionSetup.minutesStep)
            }
            Button(action: start) {
                Text("Start ↩").font(.title).padding(.horizontal, 48).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(problem != nil)
            if let problem { SessionProblemNotice(problem: problem) }
            if let noSoundNotice {
                Label(noSoundNotice, systemImage: "speaker.slash.fill").foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    VStack(spacing: 4) {
                        Image(systemName: block.kind.symbol).font(.title2).foregroundStyle(.secondary)
                        Text(block.kind.title).font(.callout)
                        Text(clockText(block.length)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(width: 150, height: 84)
                    .sessionCard()
                    .accessibilityElement(children: .combine)
                }
            }
            HStack {
                Picker("Notes", selection: $naturalsOnly) {
                    Text("Naturals").tag(true)
                    Text("All notes").tag(false)
                }
                Picker("Frets", selection: $range) {
                    ForEach(SessionRange.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 560)
        }
    }

    private func step(_ symbol: String, _ label: String, by change: Int) -> some View {
        let new = SessionSetup(minutes: shownMinutes + change).minutes
        return Button { minutes = new } label: {
            Image(systemName: symbol).font(.largeTitle)
        }
        .buttonStyle(.plain)
        .disabled(new == shownMinutes)
        .accessibilityLabel(label)
    }
}

private struct SessionProblemNotice: View {
    let problem: SessionProblem

    var body: some View {
        switch problem {
        case .input(let problem): AudioInputProblemNotice(problem: problem)
        case .nothingToPrompt(let reason): Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

extension View {
    func sessionCard() -> some View {
        background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
    }

    func sessionStatusBar() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .frame(height: 32)
            .background(.bar)
    }
}
