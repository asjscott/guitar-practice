import PracticeCore
import SwiftUI
import TheoryCore

// Layout C's pieces for the circle drills (prototype/phase4b-screens): a header with the key in large type, its
// place in the circle and the clock, wrong notes and best at the top right; and a neck kept at a real guitar's
// proportions.

/// The current key in large type, what is played in it and its place ("3 of 12"); the clock, wrong notes and best at
/// the right. With no progress (idle or paused), the resting view in place of the key.
struct CircleHeader<Resting: View>: View {
    let progress: CircleProgress?
    /// Beside the key: "every one, frets 0–12", "C shape · up ↑".
    let detail: String
    /// Now on the drill clock.
    let now: Duration
    @ViewBuilder let resting: Resting

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 16) {
            if let progress {
                Text(progress.key.shortName).font(.system(size: 72, weight: .bold))
                VStack(alignment: .leading) {
                    Text(detail).font(.title2)
                    Text("\(progress.place + 1) of \(progress.count)").foregroundStyle(.secondary)
                }
                Spacer()
                CircleClock(time: progress.time(at: now), wrongNotes: progress.wrongNotes, best: progress.best)
            } else {
                VStack(alignment: .leading, spacing: 4) { resting }
                Spacer()
            }
        }
    }
}

/// The circle's time, its wrong notes and the best: "4:12", "1 wrong", "Best 9:58".
struct CircleClock: View {
    let time: Duration
    let wrongNotes: Int
    let best: CircleResult?

    var body: some View {
        HStack(spacing: 18) {
            Label(time.clockText, systemImage: "stopwatch").monospacedDigit()
            Label("\(wrongNotes) wrong", systemImage: "xmark.circle")
                .foregroundStyle(wrongNotes > 0 ? .orange : .secondary)
            Text(best.map { "Best \($0.time.clockText)" } ?? "No best yet").foregroundStyle(.secondary)
        }
        .font(.title3)
    }
}

/// A neck over a long fret range at a real guitar's proportions, with the scale views' string spacing, rather than
/// stretched to fill the height.
struct RealProportionNeck: View {
    let diagram: FretboardDiagram

    /// Matched by eye to the scale views: about 9 frets in a frame of width / height ≈ 1.95, ruler included.
    static func aspectRatio(frets: Int) -> CGFloat { CGFloat(frets) / 9 * 1.95 }

    var body: some View {
        FretboardView(diagram: diagram, minHeight: 100)
            .aspectRatio(Self.aspectRatio(frets: diagram.frets.count), contentMode: .fit)
    }
}

/// Note circle in layout C: the header, the neck over the circle's twelve frets with the current string lit and the
/// key's found notes, and under it the sweep's place, the feedback and the next key. At the circle's end, its time
/// against the best.
struct NoteCirclePrompt<Resting: View>: View {
    let display: DrillDisplay?
    let fretboard: Fretboard
    let now: Duration
    @ViewBuilder let resting: Resting

    private var frets: ClosedRange<Int> {
        fretboard.capo...min(fretboard.capo + 12, Fretboard.frets.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CircleHeader(progress: display?.circle, detail: "every one, frets \(frets.lowerBound)–\(frets.upperBound)",
                         now: now) { resting }
            RealProportionNeck(diagram: FretboardDiagram(drill: display, on: fretboard, fretWindow: frets))
                .padding(16)
                .sessionCard()
            if let display, let circle = display.circle {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(display.subline).font(.title3)
                        Text(display.feedback).font(.title3)
                            .foregroundStyle(display.result == .wrong ? .orange : .secondary)
                    }
                    Spacer()
                    if let result = circle.result {
                        CircleEnd(result: result, best: circle.best)
                    } else if let next = circle.next {
                        Text("Next: \(next.shortName)").font(.title3).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

/// A finished circle: its time, wrong notes, and how it stands against the best.
struct CircleEnd: View {
    let result: CircleResult
    let best: CircleResult?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(result.summaryText).font(.title2.weight(.semibold).monospacedDigit())
            Text(result.comparison(with: best)).font(.title3)
                .foregroundStyle(result.isBetter(than: best) ? .green : .secondary)
        }
    }
}

extension CircleResult {
    /// "9:12 · 1 wrong", plus " · 2 skipped".
    var summaryText: String {
        var text = "\(time.clockText) · \(wrongNotes) wrong"
        if skips > 0 { text += " · \(skips) skipped" }
        return text
    }

    /// "New best: −46 s", "First clean circle", "Best 9:58", or why it can't be the best.
    func comparison(with best: CircleResult?) -> String {
        if !isComplete { return "Not finished" }
        if !isClean { return "Not clean: \(skips) skipped" }
        guard let best else { return "First clean circle" }
        if isBetter(than: best) {
            let gain = best.time - time
            return gain >= .seconds(1) ? "New best: −\(Int((gain / .seconds(1)).rounded())) s" : "New best"
        }
        return "Best \(best.time.clockText)"
    }
}

extension Duration {
    /// A stopwatch's reading, whole seconds: "0:42", "9:12", "1:02:05".
    var clockText: String {
        let seconds = Int(max(.zero, self) / .seconds(1))
        let (hours, minutes) = (seconds / 3600, seconds / 60 % 60)
        let rest = String(format: "%02d", seconds % 60)
        return hours > 0 ? "\(hours):\(String(format: "%02d", minutes)):\(rest)" : "\(minutes):\(rest)"
    }
}
