import SwiftUI

/// Settings (⌘,): an Instrument tab (tuning, capo, position system) and an Audio tab.
struct SettingsView: View {
    var body: some View {
        TabView {
            InstrumentSettingsView()
                .tabItem { Label("Instrument", systemImage: "guitars") }
            AudioSettingsView()
                .tabItem { Label("Audio", systemImage: "waveform") }
        }
    }
}

#Preview {
    SettingsView()
}
