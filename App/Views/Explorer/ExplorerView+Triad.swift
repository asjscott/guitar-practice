import SwiftUI
import TheoryCore

/// Triad mode's toolbar pickers: string set and inversion.
extension ExplorerView {
    @ToolbarContentBuilder
    var triadToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            if model.display == .triad {
                Picker("String Set", selection: $model.stringSet) {
                    ForEach(model.stringSets, id: \.self) { Text($0.name).tag($0) }
                }
                .help("String set")

                Picker("Inversion", selection: $model.inversion) {
                    ForEach(Triad.Inversion.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                .help("Inversion")
            }
        }
    }
}
