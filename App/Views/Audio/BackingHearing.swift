import ListenCore

/// How a progression drill's backing will be heard, for the notices beside Start: whether the backing's sounds were
/// fetched, and whether the input is the Mac's own microphone, which would hear the backing as notes. Shared by the
/// drill and session view models.
struct BackingHearing {
    /// Whether the input is the Mac's own microphone.
    private(set) var isInputBuiltIn = false

    /// Follows the audio input: works out again whether it is built in when its device changes.
    mutating func inputChanged(from old: AudioInputState?, to new: AudioInputState) {
        if new.device?.uid != old?.device?.uid {
            isInputBuiltIn = new.device.map { CoreAudioDevices.isBuiltIn(uid: $0.uid) } ?? false
        }
    }

    #if DEBUG
    /// For snapshots, where there is no input.
    mutating func setInputBuiltInForSnapshot() { isInputBuiltIn = true }
    #endif

    /// The notices: none fetched (then `player` plays clicks: "the drill", "Progressions"), or a built-in microphone.
    func notices(hasSounds: Bool?, player: String) -> [String] {
        var notices: [String] = []
        if hasSounds == false {
            notices.append("No backing sounds: \(player) plays clicks. " + BackingSounds.fetchHint)
        }
        if isInputBuiltIn {
            notices.append("The built-in microphone will hear the backing as notes: use the interface, or headphones.")
        }
        return notices
    }
}
