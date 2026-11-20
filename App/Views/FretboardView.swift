import SwiftUI

/// Placeholder. Phase 0 step 4: draws the neck for any tuning, highlights positions,
/// labels note names (fade/hide), and leaves room for a heatmap overlay later.
struct FretboardView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [6]))
            .overlay(Text("Fretboard").foregroundStyle(.secondary))
            .frame(height: 220)
    }
}

#Preview {
    FretboardView().padding()
}
