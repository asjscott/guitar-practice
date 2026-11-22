import SwiftUI
import TheoryCore

extension View {
    /// Calls `apply` with the tuning and capo in Settings when the view appears and whenever either changes.
    func followsInstrumentSettings(_ apply: @escaping (_ tuning: Tuning, _ capo: Int) -> Void) -> some View {
        modifier(FollowsInstrumentSettings(apply: apply))
    }
}

/// Reads the persisted tuning and capo (`@AppStorage`) once, for every screen that follows them.
private struct FollowsInstrumentSettings: ViewModifier {
    let apply: (Tuning, Int) -> Void
    @AppStorage(InstrumentSettings.Key.openPitches) private var storedOpenPitches = InstrumentSettings.defaultOpenPitches
    @AppStorage(InstrumentSettings.Key.capo) private var storedCapo = InstrumentSettings.defaultCapo

    func body(content: Content) -> some View {
        content
            .onChange(of: storedOpenPitches, initial: true) { update() }
            .onChange(of: storedCapo) { update() }
    }

    private func update() {
        apply(InstrumentSettings.tuning(from: storedOpenPitches), InstrumentSettings.capo(from: storedCapo))
    }
}
