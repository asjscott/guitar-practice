import SwiftUI

// Reusable pieces for listening screens (Settings › Audio, Tuner, Drill). Each reads the app's
// `AudioInputService` from the environment.

extension View {
    /// Marks this view as a listening screen: audio input runs while it is on screen (with any other listening
    /// screens) and stops when the last one goes. `consumer`, if given, receives the chosen channel's mono
    /// samples on the audio thread while this view is on screen (see `AudioInputConsumer`).
    func listensToAudioInput(_ consumer: AudioInputConsumer? = nil) -> some View {
        modifier(ListensToAudioInput(consumer: consumer))
    }
}

private struct ListensToAudioInput: ViewModifier {
    let consumer: AudioInputConsumer?
    @Environment(AudioInputService.self) private var audioInput
    @State private var listener = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { audioInput.startListening(listener, consumer: consumer) }
            .onDisappear { audioInput.stopListening(listener) }
    }
}

/// A horizontal input meter: green rising to yellow and red at full scale. `level` is 0–1.
struct InputMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(LinearGradient(colors: [.green, .green, .yellow, .red],
                                         startPoint: .leading, endPoint: .trailing))
                    // The gradient spans the full track; the fill reveals it up to the level.
                    .frame(width: geo.size.width)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: geo.size.width * min(max(level, 0), 1))
                    }
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("Input level")
        .accessibilityValue(Text("\(Int((level * 100).rounded())) percent"))
    }
}

/// The input line for the bottom of a listening screen: "Scarlett 2i2 · Input 1" and a meter.
/// Shows a warning icon while falling back to the default input, and says so when access is off.
struct AudioInputLine: View {
    @Environment(AudioInputService.self) private var audioInput
    var meterWidth: CGFloat = 80

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(audioInput.choice?.isFallback == true ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
            Text(label).foregroundStyle(.secondary)
            InputMeter(level: audioInput.level).frame(width: meterWidth)
        }
        .font(.caption)
        .help(audioInput.failure ?? audioInput.fallbackNotice ?? "")
    }

    private var icon: String {
        if audioInput.permission == .denied || audioInput.choice == nil { return "mic.slash" }
        if audioInput.choice?.isFallback == true || audioInput.failure != nil { return "exclamationmark.triangle.fill" }
        return "mic.fill"
    }

    private var label: String {
        if audioInput.permission == .denied { return "Microphone access is off" }
        guard let choice = audioInput.choice else { return "No input device" }
        return choice.label
    }
}

/// Says the saved interface isn't connected and the system default is in use. Empty when not falling back.
struct AudioInputFallbackNotice: View {
    @Environment(AudioInputService.self) private var audioInput

    var body: some View {
        if let notice = audioInput.fallbackNotice {
            Label {
                Text(notice)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
        }
    }
}

/// Explains that microphone access is off, with a button to System Settings › Privacy & Security › Microphone.
/// `compact` fits a Settings form row; the default fills a listening screen.
struct MicrophoneAccessDeniedView: View {
    var compact = false
    @Environment(AudioInputService.self) private var audioInput

    private static let title = "Microphone access is off"
    private static let explanation = "GuitarPractice needs microphone access to hear your guitar through your audio interface. Turn it on for GuitarPractice in System Settings › Privacy & Security › Microphone."

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 8) {
                Label(Self.title, systemImage: "mic.slash").font(.headline)
                Text(Self.explanation).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                openButton
            }
        } else {
            ContentUnavailableView {
                Label(Self.title, systemImage: "mic.slash")
            } description: {
                Text(Self.explanation)
            } actions: {
                openButton
            }
        }
    }

    private var openButton: some View {
        Button("Open System Settings") { audioInput.openMicrophonePrivacySettings() }
    }
}
