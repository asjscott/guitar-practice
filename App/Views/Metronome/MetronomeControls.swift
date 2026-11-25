import PracticeCore
import SwiftUI

// The Settings controls, shared by Settings › Metronome and the metronome panel.

/// The stored time signature and emphasis.
struct StoredMeters: DynamicProperty {
    @AppStorage(MetronomeSettings.Key.signature) private var storedSignature = MetronomeSettings.defaultSignature
    @AppStorage(MetronomeSettings.Key.emphasis) private var storedEmphasis = MetronomeSettings.defaultEmphasis

    var signature: TimeSignature { meters.signature }
    var meter: Meter { meters.meter }

    private var meters: MeterMemory { MeterMemory(signature: storedSignature, emphasis: storedEmphasis) }

    func choose(_ signature: TimeSignature?) {
        guard let signature else { return }
        var meters = meters
        meters.signature = signature
        store(meters)
    }

    func toggleEmphasis(ofBeat beat: Int) {
        var meters = meters
        meters.toggleEmphasis(ofBeat: beat)
        store(meters)
    }

    private func store(_ meters: MeterMemory) {
        storedSignature = meters.signature.name
        storedEmphasis = meters.storedEmphasis
    }
}

/// The common time signatures, beats in a bar, and the beat note.
struct TimeSignatureControls: View {
    private var meters = StoredMeters()
    private var signature: TimeSignature { meters.signature }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(TimeSignature.common, id: \.self) { button($0) }
        }
        Stepper("Beats in a bar: \(signature.beats)", value: beats, in: TimeSignature.beatCounts)
        Picker("Beat note", selection: unit) {
            ForEach(TimeSignature.units, id: \.self) { Text("\($0)").tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private func button(_ option: TimeSignature) -> some View {
        let isChosen = option == signature
        return Button { meters.choose(option) } label: {
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
        Binding(get: { signature.beats }, set: { meters.choose(TimeSignature(beats: $0, unit: signature.unit)) })
    }

    private var unit: Binding<Int> {
        Binding(get: { signature.unit }, set: { meters.choose(TimeSignature(beats: signature.beats, unit: $0)) })
    }
}

/// The bar's beats, each a button that turns its emphasis on or off.
struct EmphasisControls: View {
    private var meters = StoredMeters()

    var body: some View {
        LiveBeatsRow(meter: meters.meter, size: meters.signature.beats > 8 ? 26 : 30) { meters.toggleEmphasis(ofBeat: $0) }
    }
}

/// Sound on or off, and volume.
struct ClickSoundControls: View {
    @AppStorage(MetronomeSettings.Key.volume) private var volume = MetronomeSettings.defaultVolume
    @AppStorage(MetronomeSettings.Key.isSoundOn) private var isSoundOn = MetronomeSettings.defaultIsSoundOn

    var body: some View {
        Toggle("Sound", isOn: $isSoundOn)
        Slider(value: $volume, in: 0...1) { Text("Volume") }
            .disabled(!isSoundOn)
    }
}
