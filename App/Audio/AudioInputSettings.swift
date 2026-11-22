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
    }

    /// Empty: nothing chosen yet, so the system default input is used (without a fallback notice).
    static let defaultDeviceUID = ""
    static let defaultChannel = 1
}
