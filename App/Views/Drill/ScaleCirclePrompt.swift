import PracticeCore
import SwiftUI
import TheoryCore

/// Scale circle in layout C: the circle header (the key, its scale, position and direction, and the clock), the neck
/// zoomed to the pass's position as in the scale views, and under it the fade level, the feedback and the next key's
/// position. At the circle's end, its time against the best. When a pass ends the neck changes straight to the next
/// key, shown whole with its first note ringed: there is no preview.
struct ScaleCirclePrompt<Resting: View>: View {
    let display: DrillDisplay?
    /// What to zoom to and show at rest: where the circle starts.
    let position: Position?
    let restingMarkers: [FretboardDiagram.Marker]
    let fretboard: Fretboard
    let now: Duration
    @ViewBuilder let resting: Resting

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CircleHeader(progress: display?.circle, detail: display?.subline ?? "", now: now) { resting }
            FretboardView(diagram: diagram, minHeight: 120)
                .frame(maxHeight: .infinity)
                .padding(16)
                .sessionCard()
            if let display, let circle = display.circle {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let level = display.pass?.settings.fadeLevel { Text(level.fadeText).font(.title3) }
                        Text(display.feedback).font(.title3)
                            .foregroundStyle(display.result == .wrong ? .orange : .secondary)
                    }
                    Spacer()
                    if let result = circle.result {
                        CircleEnd(result: result, best: circle.best)
                    } else if let next = circle.next {
                        Text(["Next: \(next.shortName)", circle.nextDetail].compactMap { $0 }.joined(separator: " · "))
                            .font(.title3).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var diagram: FretboardDiagram {
        var diagram = FretboardDiagram(drill: display, on: fretboard,
                                       fretWindow: display?.pass?.fretWindow ?? position?.fretWindow)
        if display == nil { diagram.markers = restingMarkers }
        return diagram
    }
}

extension FadeLevel {
    /// "Level 0 · shown", "Level 2 · fades by 68 %", "Level 6 · roots only".
    var fadeText: String {
        guard let share = fadeTime(expected: .seconds(100)) else { return "\(self) · shown" }
        let percent = Int((share / .seconds(1)).rounded())
        return percent == 0 ? "\(self) · roots only" : "\(self) · fades by \(percent) %"
    }
}
