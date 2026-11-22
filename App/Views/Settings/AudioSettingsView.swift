import SwiftUI

/// Settings › Audio. A placeholder until the input device and channel picker land.
struct AudioSettingsView: View {
    var body: some View {
        Form {
            Section("Input") {
                Text("Audio input settings are coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    AudioSettingsView()
}
