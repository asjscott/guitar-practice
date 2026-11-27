import PracticeCore
import SwiftUI

/// Settings › Metronome: time signature, emphasis, volume, sound on or off, and Listen; and Listen for backing.
struct MetronomeSettingsView: View {
    private var meters = StoredMeters()
    @Environment(Metronome.self) private var metronome
    @Environment(AppSoundOutput.self) private var soundOutput
    @Environment(BackingPlayer.self) private var backing
    @AppStorage(MetronomeSettings.Key.backingListenHasClick) private var backingHasClick = true
    /// Listen's style is its progression's, the same one free practice remembers.
    @AppStorage(MetronomeSettings.Key.backingStyle(of: BackingPlayer.listenProgression))
    private var backingStyle = BackingPlayer.listenProgression.defaultStyle

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
                        backing.isListening ? backing.stopListening() : listen()
                    }
                    .disabled(!backing.hasSounds || !backing.isListening
                              && (backing.isRunning || metronome.isRunning && !metronome.isListening))
                } label: {
                    Text("\(BackingPlayer.listenProgression.id) in \(BackingPlayer.listenKey.shortName),\(BackingPlayer.listenBPM) BPM")
                }
                Picker("Style", selection: $backingStyle) {
                    ForEach(BackingStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(!backing.hasSounds)
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
        .onChange(of: backingHasClick) { if backing.isListening { listen() } }
        .onChange(of: backingStyle) { if backing.isListening { listen() } }
        .onChange(of: soundOutput.problem) { if soundOutput.problem != nil { stopListening() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            stopListening()
        }
        .onDisappear { stopListening() }
    }

    private func listen() {
        backing.listen(style: backingStyle, withClick: backingHasClick)
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
