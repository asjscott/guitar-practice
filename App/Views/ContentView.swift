import SwiftUI
import TheoryCore

struct ContentView: View {
    var body: some View {
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
