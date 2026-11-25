import PracticeCore
import SwiftUI

/// Settings › Metronome: time signature, emphasis, volume, sound on or off, and Listen.
struct MetronomeSettingsView: View {
    @AppStorage(MetronomeSettings.Key.signature) private var storedSignature = MetronomeSettings.defaultSignature
    @AppStorage(MetronomeSettings.Key.emphasis) private var storedEmphasis = MetronomeSettings.defaultEmphasis
    @AppStorage(MetronomeSettings.Key.volume) private var volume = MetronomeSettings.defaultVolume
    @AppStorage(MetronomeSettings.Key.isSoundOn) private var isSoundOn = MetronomeSettings.defaultIsSoundOn

    @Environment(Metronome.self) private var metronome
    @Environment(AppSoundOutput.self) private var soundOutput

    private var meters: MeterMemory { MeterMemory(signature: storedSignature, emphasis: storedEmphasis) }
    private var signature: TimeSignature { meters.signature }

    var body: some View {
        Form {
            Section("Time signature") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(TimeSignature.common, id: \.self) { signatureButton($0) }
                }
                Stepper("Beats in a bar: \(signature.beats)", value: beats, in: TimeSignature.beatCounts)
                Picker("Beat note", selection: unit) {
                    ForEach(TimeSignature.units, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                LiveBeatsRow(meter: meters.meter, size: signature.beats > 8 ? 26 : 30) { beat in
                    var meters = meters
                    meters.toggleEmphasis(ofBeat: beat)
                    store(meters)
                }
                .frame(maxWidth: .infinity)
            } header: {
                Text("Emphasis in \(signature.name)")
            } footer: {
                Text("Click a beat to change it. Every beat clicks; emphasised ones are higher and louder.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Sound", isOn: $isSoundOn)
                Slider(value: $volume, in: 0...1) { Text("Volume") }
                    .disabled(!isSoundOn)
                LabeledContent {
                    Button(metronome.isListening ? "Stop" : "Listen") {
                        metronome.isListening ? metronome.stopListening() : metronome.listen()
                    }
                    .disabled(metronome.isRunning && !metronome.isListening)
                } label: {
                    Text("\(Metronome.listenBPM) BPM, counting clicks")
                }
            } header: {
                Text("Click")
            } footer: {
                if let problem = soundOutput.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: meters.meter) { if metronome.isListening { metronome.listen() } }
        .onChange(of: soundOutput.problem) { if soundOutput.problem != nil { metronome.stopListening() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            metronome.stopListening()
        }
        .onDisappear { metronome.stopListening() }
    }

    private func signatureButton(_ option: TimeSignature) -> some View {
        let isChosen = option == signature
        return Button { choose(option) } label: {
            Text(option.name)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .foregroundStyle(isChosen ? Color.white : .primary)
                .background(isChosen ? Color.blue : .secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private var beats: Binding<Int> {
        Binding(get: { signature.beats }, set: { choose(TimeSignature(beats: $0, unit: signature.unit)) })
    }

    private var unit: Binding<Int> {
        Binding(get: { signature.unit }, set: { choose(TimeSignature(beats: signature.beats, unit: $0)) })
    }

    private func choose(_ signature: TimeSignature?) {
        guard let signature else { return }
        var meters = meters
        meters.signature = signature
        store(meters)
    }

    private func store(_ meters: MeterMemory) {
        storedSignature = meters.signature.name
        storedEmphasis = meters.storedEmphasis
    }
}

#Preview {
    let output = AppSoundOutput(isInert: true)
    MetronomeSettingsView()
        .environment(output)
        .environment(Metronome(output: output))
}
