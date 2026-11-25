import Foundation
import PracticeCore

/// The persisted metronome setup, stored with `@AppStorage` (UserDefaults). Not locked during a session.
enum MetronomeSettings {
    /// UserDefaults keys.
    enum Key {
        static let signature = "metronome.signature"
        /// The emphasis of every signature where it was chosen (`MeterMemory.storedEmphasis`).
        static let emphasis = "metronome.emphasis"
        /// 0–1.
        static let volume = "metronome.volume"
        static let isSoundOn = "metronome.isSoundOn"

        /// BPM, for each scale drill.
        static func tempo(of kind: DrillKind) -> String { "metronome.tempo.\(kind.id)" }
        /// For each scale drill.
        static func holdsTempo(of kind: DrillKind) -> String { "metronome.holdsTempo.\(kind.id)" }

        static let all = [signature, emphasis, volume, isSoundOn]
    }

    static let defaultSignature = TimeSignature.fourFour.name
    static let defaultEmphasis = ""
    static let defaultVolume = 0.8
    static let defaultIsSoundOn = true

    /// A scale drill's tempo and Hold, in sessions and free practice alike, put in place of the settings' own.
    static func loadTempo(of kind: DrillKind, into settings: inout PassSettings, from defaults: UserDefaults) {
        settings.tempo = defaults.object(forKey: Key.tempo(of: kind)) as? Int ?? PassSettings().tempo
        settings.holdsTempo = defaults.bool(forKey: Key.holdsTempo(of: kind))
    }

    static func storeTempo(of kind: DrillKind, from settings: PassSettings, in defaults: UserDefaults) {
        defaults.set(settings.tempo, forKey: Key.tempo(of: kind))
        defaults.set(settings.holdsTempo, forKey: Key.holdsTempo(of: kind))
    }

    static func meters(in defaults: UserDefaults) -> MeterMemory {
        MeterMemory(signature: defaults.string(forKey: Key.signature) ?? defaultSignature,
                    emphasis: defaults.string(forKey: Key.emphasis) ?? defaultEmphasis)
    }

    /// 0 with sound off.
    static func clickVolume(in defaults: UserDefaults) -> Float {
        guard defaults.object(forKey: Key.isSoundOn) as? Bool ?? defaultIsSoundOn else { return 0 }
        let volume = defaults.object(forKey: Key.volume) as? Double ?? defaultVolume
        return Float(min(max(volume, 0), 1))
    }
}
