import SwiftUI

/// The main window's root: hosts the fretboard explorer and owns its (unpersisted) state.
struct ContentView: View {
    @State private var model = ExplorerViewModel()

    var body: some View {
        ExplorerView(model: model)
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 420)
}
