import PracticeCore
import SwiftUI

/// The button that opens the metronome panel: "♩ = 72 · 4/4".
struct MetronomeButton: View {
    /// What the next pass is played at.
    let settings: PassSettings
    @Binding var isOpen: Bool

    var body: some View {
        Button { isOpen.toggle() } label: { Text(settings.text).monospacedDigit() }
            .help("Metronome (M); [ and ] change the tempo")
            .accessibilityLabel("Metronome, \(settings.tempo) BPM, \(settings.meter.signature.name)")
    }
}

/// BPM, Hold tempo, and the Settings controls.
struct MetronomePanel: View {
    @Binding var settings: PassSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BPMField(tempo: $settings.tempo)
                Spacer()
                Toggle("Hold tempo", isOn: $settings.holdsTempo)
                    .help("Keep the tempo whatever happens in a pass")
            }
            Divider()
            TimeSignatureControls()
            EmphasisControls().frame(maxWidth: .infinity)
            Divider()
            HStack(spacing: 16) { ClickSoundControls() }
        }
        .padding(18)
        .frame(width: 400)
    }
}

/// A tempo typed, or stepped by 4. It takes effect as soon as what is typed is a tempo; Return makes it one.
private struct BPMField: View {
    @Binding var tempo: Int
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("BPM", text: $text)
                .labelsHidden()
                .font(.title2.monospacedDigit().bold())
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .focused($isFocused)
                .onSubmit(commit)
            Text("BPM").foregroundStyle(.secondary)
            Stepper("BPM", value: $tempo, in: PassSettings.tempos, step: TempoLadder.step)
                .labelsHidden()
        }
        .onAppear { text = "\(tempo)" }
        .onChange(of: tempo) { if Int(text) != tempo { text = "\(tempo)" } }
        .onChange(of: text) {
            if let typed = Int(text), PassSettings.tempos.contains(typed) { tempo = typed }
        }
        .onChange(of: isFocused) { if !isFocused { commit() } }
    }

    /// The nearest tempo; what was there if it isn't a number.
    private func commit() {
        if let typed = Int(text) { tempo = typed }
        text = "\(tempo)"
    }
}

extension View {
    /// The panel over the top right corner, under its button. A click elsewhere closes it, and so do M and Esc; M also
    /// opens it, and [ and ] change the tempo by 4. While it is open the view's own keys are kept from acting, but
    /// those typed into it are not.
    func metronomePanel(isOpen: Binding<Bool>, isAvailable: Bool, settings: Binding<PassSettings>) -> some View {
        overlay(alignment: .topTrailing) {
            if isOpen.wrappedValue {
                ZStack(alignment: .topTrailing) {
                    Color.black.opacity(0.08)
                        .contentShape(Rectangle())
                        .onTapGesture { isOpen.wrappedValue = false }
                        .accessibilityHidden(true)
                    ViewThatFits(in: .vertical) {
                        MetronomePanel(settings: settings)
                        ScrollView { MetronomePanel(settings: settings) }.frame(width: 400)
                    }
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .padding(8)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Metronome")
                }
            }
        }
        .onPlainKey { key in
            guard isAvailable else { return false }
            switch key {
            case .character("m"):
                isOpen.wrappedValue.toggle()
                return true
            case .escape where isOpen.wrappedValue:
                isOpen.wrappedValue = false
                return true
            case .character("["), .character("]"):
                if !isOpen.wrappedValue {
                    settings.wrappedValue.tempo += key == .character("]") ? TempoLadder.step : -TempoLadder.step
                }
                return true
            case .character(let text) where isOpen.wrappedValue:
                // Digits, and what edits or moves between them: function keys are in the private use area.
                return text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
            case .character, .space, .return, .escape:
                return false
            }
        }
    }
}

#Preview {
    @Previewable @State var settings = PassSettings()
    MetronomePanel(settings: $settings)
        .environment(Metronome(output: AppSoundOutput(isInert: true)))
}
