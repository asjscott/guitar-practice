import PracticeCore
import SwiftUI

/// The beats of a bar: emphasised ones larger and blue, the current one orange. With `toggle`, each is a numbered
/// button that changes its emphasis.
struct BeatsRow: View {
    let meter: Meter
    /// From 1; nil when nothing clicks.
    let current: Int?
    /// Of an emphasised beat.
    var size: CGFloat = 26
    var toggle: ((_ beat: Int) -> Void)?

    var body: some View {
        HStack(spacing: size * 0.2) {
            ForEach(1...meter.signature.beats, id: \.self) { beat in
                if let toggle {
                    Button { toggle(beat) } label: { dot(beat).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Beat \(beat)")
                        .accessibilityValue(isEmphasised(beat) ? "Emphasised" : "Normal")
                } else {
                    dot(beat)
                }
            }
        }
        .accessibilityElement(children: toggle == nil ? .ignore : .contain)
        .accessibilityLabel("Beats in a bar: \(meter.signature.beats)")
    }

    private func isEmphasised(_ beat: Int) -> Bool { meter.emphasis.contains(beat) }

    private func dot(_ beat: Int) -> some View {
        let isLit = isEmphasised(beat) || beat == current
        // Room for a number in a dot that can be clicked.
        let scale = isEmphasised(beat) ? 1 : toggle == nil ? 0.6 : 0.7
        return Circle()
            .fill(beat == current ? Color.orange : isEmphasised(beat) ? .blue : .secondary.opacity(0.3))
            .frame(width: size * scale, height: size * scale)
            .overlay {
                if toggle != nil {
                    Text("\(beat)")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(isLit ? Color.white : .primary)
                }
            }
            .frame(width: size, height: size)
    }
}

/// The beats as the metronome plays them.
struct LiveBeatsRow: View {
    let meter: Meter
    var size: CGFloat = 26
    var toggle: ((_ beat: Int) -> Void)?
    @Environment(Metronome.self) private var metronome

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !metronome.isRunning)) { _ in
            BeatsRow(meter: meter, current: metronome.isRunning ? metronome.current(at: Metronome.now)?.beat : nil,
                     size: size, toggle: toggle)
        }
    }
}
