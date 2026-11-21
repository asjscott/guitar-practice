import SwiftUI

/// The main window's root: hosts the fretboard explorer and owns its (unpersisted) state.
/// Feeds the persisted tuning and capo from Settings into the explorer, live.
struct ContentView: View {
    @State private var model = ExplorerViewModel()
    @AppStorage(InstrumentSettings.Key.openPitches) private var storedOpenPitches = InstrumentSettings.defaultOpenPitches
    @AppStorage(InstrumentSettings.Key.capo) private var storedCapo = InstrumentSettings.defaultCapo

    var body: some View {
        ExplorerView(model: model)
            .onChange(of: storedOpenPitches, initial: true) {
                model.tuning = InstrumentSettings.tuning(from: storedOpenPitches)
            }
            .onChange(of: storedCapo, initial: true) {
                model.capo = InstrumentSettings.capo(from: storedCapo)
            }
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 420)
}
