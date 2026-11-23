import SwiftUI
import TheoryCore

/// The main window's root: a sidebar of screens (Session · Explorer · Tuner · Drill) and the selected
/// screen as the detail. Remembers the selected screen per window; Session on first launch.
///
/// Owns the session's and the explorer's (unpersisted) state, so it survives switching screens, and feeds the
/// persisted tuning, capo and position system from Settings into it, live.
struct ContentView: View {
    @SceneStorage("main.screen") private var screen: Screen = .session
    @State private var session = SessionViewModel()
    @State private var explorer = ExplorerViewModel()
    @AppStorage(InstrumentSettings.Key.positionSystem) private var positionSystem = InstrumentSettings.defaultPositionSystem

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section("Practice") {
                    ForEach(Screen.allCases) { screen in
                        Label(screen.title, systemImage: screen.icon).tag(screen)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .followsInstrumentSettings { tuning, capo in
            explorer.tuning = tuning
            explorer.capo = capo
        }
        .onChange(of: positionSystem, initial: true) {
            explorer.positionSystem = positionSystem
        }
    }

    /// The list's selection; clicking empty space can't deselect into "no screen".
    private var selection: Binding<Screen?> {
        Binding(get: { screen }, set: { if let newScreen = $0 { screen = newScreen } })
    }

    @ViewBuilder private var detail: some View {
        switch screen {
        case .session: SessionView(model: session)
        case .explorer: ExplorerView(model: explorer)
        case .tuner: TunerView()
        case .drill: DrillView()
        }
    }
}

/// A screen in the main window's sidebar. The raw value is what `@SceneStorage` saves.
enum Screen: String, CaseIterable, Identifiable {
    case session, explorer, tuner, drill

    var id: Self { self }

    var title: String {
        switch self {
        case .session: "Session"
        case .explorer: "Explorer"
        case .tuner: "Tuner"
        case .drill: "Drill"
        }
    }

    var icon: String {
        switch self {
        case .session: "timer"
        case .explorer: "guitars"
        case .tuner: "tuningfork"
        case .drill: "target"
        }
    }
}

#Preview {
    ContentView()
        .environment(AudioInputService(isInert: true))
        .environment(AttemptLog.inMemory())
        .frame(width: 1100, height: 420)
}
