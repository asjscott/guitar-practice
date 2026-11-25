import AppKit
import SwiftUI

@main
enum Main {
    @MainActor static func main() {
        #if DEBUG
        if Snapshots.isRequested { Snapshots.run() }
        if LogCheck.isRequested { LogCheck.run() }
        #endif
        GuitarPracticeApp.main()
    }
}

struct GuitarPracticeApp: App {
    /// The app's one audio input, shared by every listening screen in every window.
    @State private var audioInput = AudioInputService()

    /// The app's one sound output.
    @State private var soundOutput: AppSoundOutput

    /// The app's one metronome.
    @State private var metronome: Metronome

    /// The app's one attempt log.
    @State private var log = AttemptLog.live()

    /// The sessions going, in any window.
    @State private var activeSessions = ActiveSessions()

    init() {
        let soundOutput = AppSoundOutput()
        _soundOutput = State(initialValue: soundOutput)
        _metronome = State(initialValue: Metronome(output: soundOutput))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1100, minHeight: 400)
                .environment(audioInput)
                .environment(soundOutput)
                .environment(metronome)
                .environment(log)
                .environment(activeSessions)
        }
        .commands {
            // Replace the system "Settings…" item with one that explicitly activates
            // the app and opens (or brings forward) the single Settings window.
            CommandGroup(replacing: .appSettings) {
                OpenSettingsButton()
            }
        }

        Settings {
            SettingsView()
                .environment(audioInput)
                .environment(soundOutput)
                .environment(metronome)
                .environment(activeSessions)
        }
    }
}

/// "Settings…" menu item, bound to ⌘,. `openSettings` opens the Settings scene, or
/// brings the existing window to the front, so repeat presses never open a second one.
private struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}
