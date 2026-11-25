import PracticeCore
import SwiftUI

/// Settings › Metronome: time signature, emphasis, volume, sound on or off, and Listen.
struct MetronomeSettingsView: View {
    private var meters = StoredMeters()
    @Environment(Metronome.self) private var metronome
    @Environment(AppSoundOutput.self) private var soundOutput

    var body: some View {
        Form {
            Section("Time signature") {
                TimeSignatureControls()
            }

            Section {
                EmphasisControls().frame(maxWidth: .infinity)
            } header: {
                Text("Emphasis in \(meters.signature.name)")
            } footer: {
                Text("Click a beat to change it. Every beat clicks; emphasised ones are higher and louder.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ClickSoundControls()
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
}

#Preview {
    let output = AppSoundOutput(isInert: true)
    MetronomeSettingsView()
        .environment(output)
        .environment(Metronome(output: output))
}
