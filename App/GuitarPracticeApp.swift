import AppKit
import SwiftUI

@main
struct GuitarPracticeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 400)
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
