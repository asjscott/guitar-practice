import SwiftUI
import TheoryCore

struct ContentView: View {
    var body: some View {
        #if DEBUG
        PrototypeExplorerRoot() // PROTOTYPE — remove when the explorer layout is chosen
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        VStack(spacing: 16) {
            FretboardView()
            Text("TheoryCore \(TheoryCore.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
