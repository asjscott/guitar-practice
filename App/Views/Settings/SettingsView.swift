import SwiftUI
import TheoryCore

/// Settings (⌘,): tuning, capo and position system, persisted with `@AppStorage`.
///
/// Picking a preset sets every string; stepping any string switches the picker to Custom.
/// Each string is limited to MIDI 24–72 by TheoryCore; re-entrant tunings are allowed.
struct SettingsView: View {
    @AppStorage(InstrumentSettings.Key.tuningChoice) private var storedChoice = InstrumentSettings.defaultTuningChoice
    @AppStorage(InstrumentSettings.Key.openPitches) private var storedOpenPitches = InstrumentSettings.defaultOpenPitches
    @AppStorage(InstrumentSettings.Key.capo) private var storedCapo = InstrumentSettings.defaultCapo
    @AppStorage(InstrumentSettings.Key.positionSystem) private var positionSystem = InstrumentSettings.defaultPositionSystem

    private var tuning: Tuning { InstrumentSettings.tuning(from: storedOpenPitches) }

    private var choice: Binding<TuningChoice> {
        Binding(
            get: { TuningChoice(rawValue: storedChoice) ?? .custom },
            set: { newChoice in
                storedChoice = newChoice.rawValue
                if case .preset(let preset) = newChoice {
                    storedOpenPitches = InstrumentSettings.encode(preset.tuning)
                }
            })
    }

    private var capo: Binding<Int> {
        Binding(get: { InstrumentSettings.capo(from: storedCapo) }, set: { storedCapo = $0 })
    }

    var body: some View {
        Form {
            Section("Tuning") {
                Picker("Tuning", selection: choice) {
                    ForEach(TuningChoice.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                // Labelled 6 to 1: index 0 (string 6) first.
                ForEach(tuning.strings, id: \.self) { string in
                    stringRow(string)
                }
            }

            Section("Capo") {
                Picker("Capo", selection: capo) {
                    Text("None").tag(0)
                    ForEach(1...Fretboard.capoFrets.upperBound, id: \.self) { Text("Fret \($0)").tag($0) }
                }
            }

            Section {
                Picker("Position system", selection: $positionSystem) {
                    ForEach(Position.System.allCases, id: \.self) { Text($0.settingsName).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Positions")
            } footer: {
                Text(positionsFooter)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Which scales have 3NPS patterns, from TheoryCore: for example "3NPS patterns exist for
    /// major and natural minor only; major pentatonic, minor pentatonic and blues always use
    /// the five CAGED shapes."
    private var positionsFooter: String {
        let kinds = Scale.Kind.allCases
        let sevenNote = kinds.filter(\.isSevenNote).map(\.name).formatted(.list(type: .and))
        let others = kinds.filter { !$0.isSevenNote }.map(\.name).formatted(.list(type: .and))
        return "3NPS patterns exist for \(sevenNote) only; \(others) always use the five CAGED shapes."
    }

    private func stringRow(_ string: Int) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                // Spelled by TheoryCore: flats for a flat-named preset (E♭ standard), else sharps.
                Text(tuning.openPitchNames[string])
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 36, alignment: .trailing)
                Stepper("String \(tuning.stringNumber(ofString: string)) open pitch",
                        value: openMIDI(string), in: Tuning.openPitchRange.lowerBound.midi...Tuning.openPitchRange.upperBound.midi)
                    .labelsHidden()
            }
        } label: {
            Text("String \(tuning.stringNumber(ofString: string))")
        }
    }

    /// One string's open pitch as a MIDI number for the stepper (which disables itself at 24 and 72).
    /// Setting it retunes through TheoryCore and makes the tuning Custom.
    private func openMIDI(_ string: Int) -> Binding<Int> {
        Binding(
            get: { tuning.openPitch(ofString: string).midi },
            set: { newMIDI in
                let step = Pitch(newMIDI) - tuning.openPitch(ofString: string)
                guard step != .unison, tuning.canRetune(string: string, by: step) else { return }
                storedOpenPitches = InstrumentSettings.encode(tuning.retuning(string: string, by: step))
                storedChoice = TuningChoice.custom.rawValue
            })
    }
}

#Preview {
    SettingsView()
}
