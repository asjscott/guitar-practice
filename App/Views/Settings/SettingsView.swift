import SwiftUI

/// Settings (⌘,): an Instrument tab (tuning, capo, position system), an Audio tab and a Metronome tab.
struct SettingsView: View {
    var body: some View {
        TabView {
            InstrumentSettingsView()
                .tabItem { Label("Instrument", systemImage: "guitars") }
            AudioSettingsView()
                .tabItem { Label("Audio", systemImage: "waveform") }
            MetronomeSettingsView()
                .tabItem { Label("Metronome", systemImage: "metronome") }
        }
    }
}

#Preview {
    let output = AppSoundOutput(isInert: true)
    SettingsView()
        .environment(AudioInputService())
        .environment(output)
        .environment(Metronome(output: output))
}
