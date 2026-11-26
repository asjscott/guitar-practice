import PracticeCore
import SwiftUI
import TheoryCore

/// After a session: its total time, a card per block that started (narrowing to fit the window), and the slowest prompts.
struct SessionSummaryView: View {
    let summary: SessionSummary
    let tuning: Tuning
    /// The theme's, for spelling.
    let key: Key?
    let done: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(clockText(summary.totalTime)).font(.system(size: 84, weight: .bold, design: .rounded)).monospacedDigit()
            HStack(spacing: summary.blocks.count > 5 ? 8 : 16) {
                ForEach(Array(summary.blocks.enumerated()), id: \.offset) { _, block in card(block) }
            }
            if summary.hasNoAttempts {
                Text("No prompts done, so nothing was saved.").foregroundStyle(.secondary)
            } else {
                slowest
                AttemptLogNotice()
            }
            Button("Done ↩", action: done).controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var slowest: some View {
        let attempts = summary.slowest(3)
        if !attempts.isEmpty {
            VStack {
                Text("Slowest").font(.headline)
                ForEach(Array(attempts.enumerated()), id: \.offset) { _, attempt in
                    Text(attempt.summaryLine(in: tuning, key: key)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func promptsText(_ stats: RunStats) -> String {
        "\(stats.prompts) \(stats.prompts == 1 ? "prompt" : "prompts") · \(stats.skips) skipped"
    }

    /// The big number, the line under it, and the details under the drill's name.
    private func lines(of block: SessionSummary.Block) -> (main: String, sub: String?, detail: String) {
        if let chords = block.chords {
            // "31 of 40" chords clean; the times through and when it went Hidden; the two hardest chords.
            var through = "\(chords.timesThrough) \(chords.timesThrough == 1 ? "time" : "times") through"
            if let firstHidden = chords.firstHidden { through += " · Hidden from the \(firstHidden.ordinal)" }
            let hardest = chords.hardest.isEmpty ? nil : "Hardest: " + chords.hardest.map(\.text).joined(separator: ", ")
            return (chords.chords == 0 ? "–" : "\(chords.clean) of \(chords.chords)", "chords clean",
                    [through, hardest].compactMap { $0 }.joined(separator: "\n"))
        }
        if let passes = block.passes { return (passes.cleanText, passes.tempoText, passes.detailText) }
        return (block.stats.firstTryText, block.speedText, promptsText(block.stats))
    }

    private func card(_ block: SessionSummary.Block) -> some View {
        let lines = lines(of: block)
        return VStack(spacing: 4) {
            Image(systemName: block.kind.symbol).font(.title2).foregroundStyle(.secondary)
            Text(lines.main).font(.system(size: 40, weight: .bold, design: .rounded))
            Text(lines.sub ?? " ").font(.title3.monospacedDigit())
            Text(block.kind.title).font(.callout)
            Text(lines.detail).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 6)
        .frame(minWidth: 84, maxWidth: 190)
        .frame(height: 180)
        .sessionCard()
        .accessibilityElement(children: .combine)
    }
}
