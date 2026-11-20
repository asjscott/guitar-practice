import SwiftUI

/// Placeholder. Phase 0 step 5: tuning picker (presets + custom per string), capo,
/// position system (CAGED / 3NPS).
struct SettingsView: View {
    var body: some View {
        Form {
            Text("Tuning, capo and position system go here.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 420, height: 240)
    }
}

#Preview {
    SettingsView()
}
