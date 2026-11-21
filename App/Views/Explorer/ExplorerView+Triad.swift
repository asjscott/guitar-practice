import SwiftUI
import TheoryCore

/// Triad mode's toolbar controls: quality (major/minor), string set and inversion.
extension ExplorerView {
    @ToolbarContentBuilder
    var triadToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            if model.display == .triad {
                Picker("Quality", selection: $model.mode) {
                    Text("Major").tag(Key.Mode.major)
                    Text("Minor").tag(Key.Mode.minor)
                }
                .pickerStyle(.segmented)
                .help("Major or minor triad")

                Picker("String Set", selection: $model.stringSet) {
                    ForEach(model.stringSets, id: \.self) { Text($0.name).tag($0) }
                }
                .help("String set")

                Picker("Inversion", selection: $model.inversionChoice) {
                    Text(InversionChoice.all.name).tag(InversionChoice.all)
                    Divider()
                    ForEach(Triad.Inversion.allCases, id: \.self) { inversion in
                        Text(inversion.name).tag(InversionChoice.single(inversion))
                    }
                }
                .help("Inversion")
            }
        }
    }
}
