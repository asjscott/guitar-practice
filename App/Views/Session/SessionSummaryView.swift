import PracticeCore
import SwiftUI
import TheoryCore

/// After a session, layout C (prototype/phase4b-screens): the rail with each step's result, and beside it the headline,
/// the circles' times against your best, the Scale circle's time per key and the fade levels that moved. A session
/// ended early shows only the blocks played.
struct SessionSummaryView: View {
    let summary: SessionSummary
    /// The rail's steps, as the session left them.
    let steps: [RailStep]
    let done: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SessionRail(title: "Done", steps: summary.endedEarly ? steps.filter { $0.state == .done } : steps)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(summary.headline).font(.system(size: 34, weight: .bold))
                    if summary.endedEarly {
                        played
                    } else {
                        circles
                        scaleCircleKeys
                        fadeMoves
                    }
                    if summary.hasNoAttempts {
                        Text("No prompts done, so nothing was saved.").foregroundStyle(.secondary)
                    } else {
                        AttemptLogNotice()
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    Button("Done ↩", action: done).controlSize(.large)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
            }
        }
    }

    /// Ended early: each block played and how it went.
    private var played: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(summary.blocks, id: \.step) { block in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(block.kind.title).font(.title3.weight(.semibold)).frame(width: 190, alignment: .leading)
                    Text(block.resultText).font(.title3).monospacedDigit()
                    if let circle = block.circle, circle.isComplete {
                        Text(circle.comparison(with: block.circleBest))
                            .foregroundStyle(circle.isBetter(than: block.circleBest) ? .green : .secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var circles: some View {
        if !summary.circles.isEmpty {
            Text("Circles against your best").font(.headline)
            HStack(spacing: 20) {
                ForEach(summary.circles, id: \.step) { block in
                    if let circle = block.circle { card(block.kind, circle, best: block.circleBest) }
                }
            }
        }
    }

    private func card(_ kind: DrillKind, _ circle: CircleResult, best: CircleResult?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(kind.title).foregroundStyle(.secondary)
            Text(circle.time.clockText).font(.system(size: 36, weight: .bold).monospacedDigit())
            Text("\(circle.wrongNotes) wrong" + (circle.skips > 0 ? " · \(circle.skips) skipped" : ""))
                .monospacedDigit()
            Text(circle.comparison(with: best))
                .foregroundStyle(circle.isBetter(than: best) ? .green : .secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(14)
        .frame(width: 190, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.secondary.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var scaleCircleKeys: some View {
        let keys = summary.scaleCircleKeys
        if !keys.isEmpty {
            Text("Scale circle per key").font(.headline)
            HStack(spacing: 6) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    VStack {
                        Text(key.key.shortName).font(.headline)
                        Text(key.time.clockText).font(.caption.monospacedDigit())
                    }
                    .frame(width: 52)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder private var fadeMoves: some View {
        Text("Fade levels").font(.headline)
        if summary.fadeMoves.isEmpty {
            Text("None moved today.").foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(summary.fadeMoves, id: \.self) { move in
                    Text(move.text).foregroundStyle(move.to > move.from ? .primary : .secondary)
                }
            }
        }
    }
}
