import Foundation
import ListenCore

/// The persisted audio input choice, in UserDefaults (the same store as `@AppStorage`).
enum AudioInputSettings {
    /// UserDefaults keys.
    enum Key {
        /// Core Audio device UID of the chosen input device.
        static let deviceUID = "audio.deviceUID"
        /// The chosen device's name, kept only to name it in the fallback notice while it is unplugged.
        static let deviceName = "audio.deviceName"
        /// 1-based input channel ("Input 1").
        static let channel = "audio.channel"
        /// Seconds: an input device's input delay, measured by the latency check.
        static func inputDelay(ofDevice uid: String) -> String { "audio.inputDelay.\(uid)" }
    }

    /// Empty: nothing chosen yet, so the system default input is used (without a fallback notice).
    static let defaultDeviceUID = ""
    static let defaultChannel = 1

    /// Forgets a saved temporary device (#20): it never comes back, so the system default input is used, without
    /// a fallback notice. The saved channel stays.
    static func forgetTemporaryDevice(in defaults: UserDefaults) {
        guard let uid = defaults.string(forKey: Key.deviceUID), AudioInputDevice.isTemporary(uid: uid) else { return }
        defaults.removeObject(forKey: Key.deviceUID)
        defaults.removeObject(forKey: Key.deviceName)
    }

    /// An input device's input delay as last measured; nil if the latency check hasn't run on it.
    static func measuredInputDelay(ofDevice uid: String, in defaults: UserDefaults) -> Duration? {
        (defaults.object(forKey: Key.inputDelay(ofDevice: uid)) as? Double).map { .seconds($0) }
    }

    /// What drills take off onsets heard from a device: zero with none, or before the latency check has run on it.
    static func inputDelay(ofDevice uid: String?, in defaults: UserDefaults = .standard) -> Duration {
        uid.flatMap { measuredInputDelay(ofDevice: $0, in: defaults) } ?? .zero
    }

    static func store(inputDelay: Duration, ofDevice uid: String, in defaults: UserDefaults) {
        defaults.set(inputDelay / .seconds(1), forKey: Key.inputDelay(ofDevice: uid))
    }
}
