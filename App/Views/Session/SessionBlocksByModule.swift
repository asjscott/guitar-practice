import PracticeCore
import SwiftUI

/// A plan's blocks as cards, side by side, under the titles of their modules. The cards narrow to fit the window.
struct SessionBlocksByModule: View {
    let blocks: [SessionBlock]

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(DrillModule.groups(of: blocks, by: \.kind.module), id: \.module) { group in
                VStack(spacing: 6) {
                    Text(group.module.title).font(.headline).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(group.members, id: \.kind) { card($0) }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(group.module.title)
                .layoutPriority(Double(group.members.count))
            }
        }
        .padding(.horizontal, 24)
    }

    private func card(_ block: SessionBlock) -> some View {
        VStack(spacing: 4) {
            Image(systemName: block.kind.symbol).font(.title2).foregroundStyle(.secondary)
            Text(block.kind.title).font(.callout).lineLimit(1).minimumScaleFactor(0.75)
            Text(clockText(block.length)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .frame(minWidth: 84, maxWidth: blocks.count > 5 ? 98 : 150)
        .frame(height: 84)
        .sessionCard()
        .accessibilityElement(children: .combine)
    }
}
