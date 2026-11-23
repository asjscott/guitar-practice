import AppKit
import SwiftUI

@main
enum Main {
    @MainActor static func main() {
        #if DEBUG
        if Snapshots.isRequested { Snapshots.run() }
        #endif
        GuitarPracticeApp.main()
    }
}

struct GuitarPracticeApp: App {
    /// The app's one audio input, shared by every listening screen in every window.
    @State private var audioInput = AudioInputService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1100, minHeight: 400)
                .environment(audioInput)
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
