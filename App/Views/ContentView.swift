import SwiftUI
import TheoryCore

/// The main window's root: hosts the fretboard explorer and owns its (unpersisted) state.
/// Feeds the persisted tuning, capo and position system from Settings into the explorer, live.
struct ContentView: View {
    @State private var model = ExplorerViewModel()
    @AppStorage(InstrumentSettings.Key.openPitches) private var storedOpenPitches = InstrumentSettings.defaultOpenPitches
    @AppStorage(InstrumentSettings.Key.capo) private var storedCapo = InstrumentSettings.defaultCapo
    @AppStorage(InstrumentSettings.Key.positionSystem) private var positionSystem = InstrumentSettings.defaultPositionSystem

    var body: some View {
        ExplorerView(model: model)
            .onChange(of: storedOpenPitches, initial: true) {
                model.tuning = InstrumentSettings.tuning(from: storedOpenPitches)
            }
            .onChange(of: storedCapo, initial: true) {
                model.capo = InstrumentSettings.capo(from: storedCapo)
            }
            .onChange(of: positionSystem, initial: true) {
                model.positionSystem = positionSystem
            }
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 420)
}
