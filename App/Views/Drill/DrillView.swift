import SwiftUI

/// The Note → play it drill screen. A placeholder until the drill engine lands.
struct DrillView: View {
    var body: some View {
        ContentUnavailableView("Note → play it", systemImage: "target",
                               description: Text("Coming soon: play the named note on the lit string, against the clock."))
            .navigationTitle("Note → play it")
    }
}

#Preview {
    DrillView()
}
