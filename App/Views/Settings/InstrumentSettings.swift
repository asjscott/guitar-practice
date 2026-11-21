import TheoryCore

/// The persisted instrument setup: tuning, capo and position system, stored with `@AppStorage` (UserDefaults).
///
/// Values are stored as plain strings and ints; reading them back always yields something
/// TheoryCore accepts, falling back to standard tuning and no capo if what is stored is unusable.
enum InstrumentSettings {
    /// UserDefaults keys.
    enum Key {
        static let tuningChoice = "tuning.choice"
        static let openPitches = "tuning.openPitches"
        static let capo = "capo"
        /// `Position.System` raw value: "caged" or "threeNotesPerString".
        static let positionSystem = "positionSystem"
    }

    /// The UI is fixed at six strings, though the model allows any count.
    static let stringCount = 6

    static let defaultTuningChoice = TuningChoice.preset(.standard).rawValue
    static let defaultOpenPitches = encode(.standard)
    static let defaultCapo = 0
    static let defaultPositionSystem = Position.System.caged

    /// Open pitches as comma-separated MIDI numbers, string 6 first ("40,45,50,55,59,64").
    static func encode(_ tuning: Tuning) -> String {
        tuning.openPitches.map { String($0.midi) }.joined(separator: ",")
    }

    /// The stored tuning, or standard if it is not six strings within MIDI 24–72.
    static func tuning(from stored: String) -> Tuning {
        let midi = stored.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard midi.count == stringCount, midi.count == stored.split(separator: ",").count else { return .standard }
        let tuning = Tuning(midi.map(Pitch.init))
        return tuning.isWithinOpenPitchRange ? tuning : .standard
    }

    /// The stored capo, clamped to 0–12.
    static func capo(from stored: Int) -> Int {
        min(max(stored, Fretboard.capoFrets.lowerBound), Fretboard.capoFrets.upperBound)
    }
}

extension Position.System {
    /// The name in the Settings picker.
    var settingsName: String {
        switch self {
        case .caged: "CAGED"
        case .threeNotesPerString: "3NPS"
        }
    }
}

/// What the tuning picker shows: a preset, or Custom once any string has been edited.
enum TuningChoice: Hashable, RawRepresentable {
    case preset(TuningPreset)
    case custom

    init?(rawValue: String) {
        if rawValue == "custom" {
            self = .custom
        } else if let preset = TuningPreset(rawValue: rawValue) {
            self = .preset(preset)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .preset(let preset): preset.rawValue
        case .custom: "custom"
        }
    }

    var name: String {
        switch self {
        case .preset(let preset): preset.name
        case .custom: "Custom"
        }
    }

    static let allCases: [TuningChoice] = TuningPreset.allCases.map(TuningChoice.preset) + [.custom]
}
