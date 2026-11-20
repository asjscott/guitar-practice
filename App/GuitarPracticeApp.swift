import SwiftUI

@main
struct GuitarPracticeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 400)
        }

        Settings {
            SettingsView()
        }
    }
}
