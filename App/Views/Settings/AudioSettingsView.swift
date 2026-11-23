import SwiftUI

/// Settings › Audio: input device and channel, with a live input meter. A listening screen, so audio input
/// runs while this tab is showing.
struct AudioSettingsView: View {
    @Environment(AudioInputService.self) private var audioInput

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
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .listensToAudioInput()
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
}

#Preview {
    AudioSettingsView()
        .environment(AudioInputService())
}
