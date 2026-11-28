import PracticeCore
import SwiftUI

/// Layout C's rail (prototype/phase4b-screens): the routine's eight steps down the left side of the Session screen, each
/// done, current or to come, or left out, with a line under it: at setup what it does today, while current where it
/// has got to ("F♯ · 3 of 12"), once done how it went.
struct SessionRail: View {
    /// "Today", "Session · 18:20".
    let title: String
    let steps: [RailStep]

    static let width: CGFloat = 250

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).monospacedDigit().padding(.bottom, 8)
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in row(step) }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.secondary.opacity(0.06))
    }

    private func row(_ step: RailStep) -> some View {
        let isCurrent = step.state == .current
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol(of: step.state)).foregroundStyle(colour(of: step.state))
            VStack(alignment: .leading, spacing: 1) {
                Text(step.kind.title).font(.callout.weight(isCurrent ? .bold : .regular))
                    .foregroundStyle(step.state == .leftOut ? .secondary : .primary)
                if !step.detail.isEmpty {
                    Text(step.detail).font(.caption).monospacedDigit()
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(isCurrent ? Color.orange.opacity(0.15) : .clear))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func symbol(of state: RailStep.State) -> String {
        switch state {
        case .done: "checkmark.circle.fill"
        case .current: "play.circle.fill"
        case .toCome: "circle"
        case .leftOut: "minus.circle"
        }
    }

    private func colour(of state: RailStep.State) -> Color {
        switch state {
        case .done: .green
        case .current: .orange
        case .toCome, .leftOut: .secondary
        }
    }
}
