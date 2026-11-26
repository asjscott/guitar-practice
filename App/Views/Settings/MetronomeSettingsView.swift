import PracticeCore
import SwiftUI

/// Settings › Metronome: time signature, emphasis, volume, sound on or off, and Listen; and Listen for backing.
struct MetronomeSettingsView: View {
    private var meters = StoredMeters()
    @Environment(Metronome.self) private var metronome
    @Environment(AppSoundOutput.self) private var soundOutput
    @Environment(BackingPlayer.self) private var backing
    @AppStorage(MetronomeSettings.Key.backingListenHasClick) private var backingHasClick = true

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
                    .disabled(metronome.isRunning && !metronome.isListening || backing.isRunning)
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

            Section {
                LabeledContent {
                    Button(backing.isListening ? "Stop" : "Listen") {
                        backing.isListening ? backing.stopListening() : backing.listen(withClick: backingHasClick)
                    }
                    .disabled(!backing.hasSounds || !backing.isListening
                              && (backing.isRunning || metronome.isRunning && !metronome.isListening))
                } label: {
                    Text("I–V–vi–IV in G, \(BackingPlayer.listenStyle.rawValue), \(BackingPlayer.listenBPM) BPM")
                }
                Toggle("With the click", isOn: $backingHasClick)
                    .disabled(!backing.hasSounds)
            } header: {
                Text("Backing")
            } footer: {
                if !backing.hasSounds {
                    Label(BackingSounds.fetchHint, systemImage: "speaker.slash")
                } else {
                    Text("Bass, keys and drums. With the click on, it should land with the drums.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: meters.meter) { if metronome.isListening { metronome.listen() } }
        .onChange(of: backingHasClick) { if backing.isListening { backing.listen(withClick: backingHasClick) } }
        .onChange(of: soundOutput.problem) { if soundOutput.problem != nil { stopListening() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            stopListening()
        }
        .onDisappear { stopListening() }
    }

    private func stopListening() {
        metronome.stopListening()
        backing.stopListening()
    }
}

#Preview {
    let output = AppSoundOutput(isInert: true)
    let metronome = Metronome(output: output)
    MetronomeSettingsView()
        .environment(output)
        .environment(metronome)
        .environment(BackingPlayer(output: output, metronome: metronome))
}
