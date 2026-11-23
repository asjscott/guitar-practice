import PracticeCore
import SwiftUI
import TheoryCore

/// After a session: its total time, a card per block that started, and the slowest prompts.
struct SessionSummaryView: View {
    let summary: SessionSummary
    let tuning: Tuning
    let done: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(clockText(summary.totalTime)).font(.system(size: 84, weight: .bold, design: .rounded)).monospacedDigit()
            HStack(spacing: 16) {
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
                    Text(attempt.summaryLine(in: tuning)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func card(_ block: SessionSummary.Block) -> some View {
        VStack(spacing: 4) {
            Image(systemName: block.kind.symbol).font(.title2).foregroundStyle(.secondary)
            Text(block.stats.firstTryText).font(.system(size: 40, weight: .bold, design: .rounded))
            Text(block.speedText ?? " ").font(.title3.monospacedDigit())
            Text(block.kind.title).font(.callout)
            Text("\(block.stats.prompts) \(block.stats.prompts == 1 ? "prompt" : "prompts") · \(block.stats.skips) skipped")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 170, height: 180)
        .sessionCard()
        .accessibilityElement(children: .combine)
    }
}
