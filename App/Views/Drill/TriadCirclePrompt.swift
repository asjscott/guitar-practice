import PracticeCore
import SwiftUI
import TheoryCore

/// Triad circle in layout C: the circle's header (`CircleHeader`), the neck over the climb's frets at real
/// proportions with the string set lit, the climb's line of voicings and a circle per string, then the voicing's place,
/// direction and fade level, the feedback and the next key. At the circle's end, its time against the best.
struct TriadCirclePrompt<Resting: View>: View {
    let display: DrillDisplay?
    let frets: ClosedRange<Int>
    let fretboard: Fretboard
    let now: Duration
    @ViewBuilder let resting: Resting

    /// "major · D-G-B · climb".
    private var detail: String {
        guard let display, let circle = display.circle else { return "" }
        let set = StringSet.allCases.first { Set($0.strings) == display.highlightedStrings }
        return [circle.key.mode.rawValue, set?.name, "climb"].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CircleHeader(progress: display?.circle, detail: detail, now: now) { resting }
            RealProportionNeck(diagram: FretboardDiagram(drill: display, on: fretboard, fretWindow: frets))
                .padding(16)
                .sessionCard()
            if let display, let circle = display.circle {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(display.headline).font(.title3.weight(.semibold))
                        Text(display.subline).font(.title3)
                        Text(display.feedback).font(.title3)
                            .foregroundStyle(display.result == .wrong ? .orange : .secondary)
                    }
                    Spacer()
                    VStack(spacing: 8) {
                        ClimbLine(voicings: display.voicings)
                        TriadCircles(chips: display.chips, size: 44)
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
