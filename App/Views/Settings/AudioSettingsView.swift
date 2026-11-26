import ListenCore
import PracticeCore
import SwiftUI

/// Settings › Audio: input device and channel, with a live input meter, and the latency check. A listening screen,
/// so audio input runs while this tab is showing.
struct AudioSettingsView: View {
    @Environment(AudioInputService.self) private var audioInput
    @Environment(AppSoundOutput.self) private var soundOutput
    @Environment(Metronome.self) private var metronome
    @Environment(BackingPlayer.self) private var backing
    @State private var check: LatencyCheckModel

    init(check: LatencyCheckModel = LatencyCheckModel()) {
        _check = State(initialValue: check)
    }

    var body: some View {
        Form {
            if audioInput.permission == .denied {
                Section {
                    MicrophoneAccessDeniedView(compact: true)
                }
            }
            Section {
                if let choice = audioInput.choice {
                    Picker("Device", selection: deviceSelection) {
                        ForEach(audioInput.devices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    Picker("Channel", selection: channelSelection) {
                        ForEach(1...max(choice.device.channelCount, 1), id: \.self) { channel in
                            Text("Input \(channel)").tag(channel)
                        }
                    }
                    LabeledContent("Level") {
                        InputMeter(level: audioInput.level).frame(width: 180)
                    }
                } else {
                    Text("No audio input devices found. Connect your audio interface.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Input")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    AudioInputFallbackNotice()
                    if let failure = audioInput.failure {
                        Label(failure, systemImage: "exclamationmark.octagon.fill")
                    }
                }
                .font(.callout)
            }

            if let device = audioInput.choice?.device {
                inputDelaySection(device)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .listensToAudioInput(check.audioConsumer)
        .onChange(of: audioInput.state) { if audioInput.state.problem != nil { check.stop() } }
        .onChange(of: audioInput.choice?.device.uid) { check.stop() }
        .onChange(of: soundOutput.problem) { if soundOutput.problem != nil { check.stop() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            check.stop()
        }
        .onDisappear { check.stop() }
    }

    private var deviceSelection: Binding<String> {
        Binding(get: { audioInput.choice?.device.uid ?? "" },
                set: { uid in
                    if let device = audioInput.devices.first(where: { $0.uid == uid }) { audioInput.selectDevice(device) }
                })
    }

    private var channelSelection: Binding<Int> {
        Binding(get: { audioInput.choice?.channel ?? 1 }, set: { audioInput.selectChannel($0) })
    }

    // MARK: - Latency check

    private func inputDelaySection(_ device: AudioInputDevice) -> some View {
        let delay = check.inputDelay(ofDevice: device.uid)
        return Section {
            LabeledContent {
                Button(check.isRunning ? "Stop" : delay == nil ? "Run check" : "Run again") {
                    check.isRunning ? check.stop() : check.start(on: device, metronome: metronome)
                }
                .disabled(!check.isRunning && checkProblem != nil)
            } label: {
                Text(check.isRunning ? progressText : delay.map(Self.millisecondsText) ?? "Not measured")
                    .monospacedDigit()
            }
        } header: {
            Text("Input delay")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if case .tooFew(let heard) = check.stage {
                    Label("Heard \(heard) of the \(LatencyCheck.clicks) clicks. Try again.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if let checkProblem, !check.isRunning {
                    Label(checkProblem, systemImage: "exclamationmark.triangle.fill")
                }
                Text("How late the app hears a pluck from \(device.name). After a bar of count-in, play a short "
                     + "palm-muted note on each of \(LatencyCheck.clicks) clicks at \(LatencyCheck.bpm) BPM. "
                     + "It is taken off every note timed against clicks or backing.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private static func millisecondsText(_ delay: Duration) -> String {
        "\(Int((delay / .milliseconds(1)).rounded())) ms"
    }

    private var progressText: String {
        switch check.progress {
        case .countIn(let beat): "Count-in · \(beat)"
        case .click(let click): "Click \(click) of \(LatencyCheck.clicks)"
        case nil: "Starting…"
        }
    }

    /// Why the check can't run; nil when it can.
    private var checkProblem: String? {
        if let problem = audioInput.state.problem { return problem.text }
        if let problem = soundOutput.problem { return problem }
        if metronome.isRunning || backing.isRunning { return "The click is in use." }
        if !metronome.clicksSound { return "The click’s sound is off, in Metronome." }
        return nil
    }
}

#Preview {
    let output = AppSoundOutput(isInert: true)
    let metronome = Metronome(output: output)
    AudioSettingsView()
        .environment(AudioInputService())
        .environment(output)
        .environment(metronome)
        .environment(BackingPlayer(output: output, metronome: metronome))
}
