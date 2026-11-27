import ListenCore
import PracticeCore
import SwiftUI

/// Why a session can't start.
enum SessionProblem: Equatable {
    case input(AudioInputProblem)
    case nothingToPrompt(String)
}

/// Before a session, layout C: the rail with each step's details; today's key large, the theme, its position on a
/// whole neck, what is left out and why, the note drills' notes and frets, an estimate and Start (↩).
struct SessionSetupView: View {
    @Binding var naturalsOnly: Bool
    @Binding var range: SessionRange
    /// Nil until it is known.
    let theme: SessionTheme?
    /// Nil once it can't be rerolled.
    let reroll: (() -> Void)?
    let steps: [RailStep]
    /// "About 33 minutes, then free time"; nil before there are three past sessions.
    var estimate: String?
    let problem: SessionProblem?
    /// Nil with sound.
    var noSoundNotice: String?
    /// What is left out, and why.
    var notices: [String] = []
    /// How a progression block's backing will be heard.
    var backingNotices: [String] = []
    let start: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SessionRail(title: "Today", steps: steps)
                Divider()
                ViewThatFits(in: .vertical) {
                    choices(neck: theme?.neck)
                    choices(neck: nil)      // in a short window
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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

    private func choices(neck: FretboardDiagram?) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(theme?.key.tonic.description ?? " ").font(.system(size: 110, weight: .bold))
                HStack {
                    Text(themeText).font(.title2)
                    if let reroll { Button("Reroll", action: reroll) }
                }
                .frame(minHeight: 28)
            }
            if let neck { FretboardView(diagram: neck, minHeight: 130).frame(maxHeight: 220) }
            noticeList
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
            .frame(maxWidth: 480)
            .help("For the note drills")
            HStack {
                if let estimate { Text(estimate).font(.title3).foregroundStyle(.secondary) }
                Spacer()
                Button(action: start) {
                    Text("Start ↩").font(.title2).padding(.horizontal, 28).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(problem != nil)
            }
        }
        .padding(28)
    }

    /// "major · E shape · D-G-B · I–V–vi–IV".
    private var themeText: String {
        guard let theme else { return "" }
        return [theme.key.mode.rawValue, theme.positionName ?? "", theme.theme.stringSet?.name ?? "",
                theme.theme.progression?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder private var noticeList: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let problem { SessionProblemNotice(problem: problem) }
            if let noSoundNotice {
                Label(noSoundNotice, systemImage: "speaker.slash.fill").foregroundStyle(.orange)
            }
            ForEach(notices, id: \.self) { Label($0, systemImage: "info.circle").foregroundStyle(.secondary) }
            ForEach(backingNotices, id: \.self) {
                Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
