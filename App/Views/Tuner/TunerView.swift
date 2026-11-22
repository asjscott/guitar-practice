import SwiftUI

/// The tuner screen. A placeholder until audio input and pitch detection land.
struct TunerView: View {
    var body: some View {
        ContentUnavailableView("Tuner", systemImage: "tuningfork",
                               description: Text("Coming soon: play a string and see how far it is from in tune."))
            .navigationTitle("Tuner")
    }
}

#Preview {
    TunerView()
}
