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
        /// The tempo ladder's count (`TempoLadder.notClean`), for each scale drill.
        static func notClean(of kind: DrillKind) -> String { "metronome.notClean.\(kind.id)" }

        /// Whether backing's Listen has the click on top.
        static let backingListenHasClick = "backing.listenHasClick"

        static let all = [signature, emphasis, volume, isSoundOn, backingListenHasClick]
    }

    static let defaultSignature = TimeSignature.fourFour.name
    static let defaultEmphasis = ""
    static let defaultVolume = 0.8
    static let defaultIsSoundOn = true

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
