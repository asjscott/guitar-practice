/// An audio device with at least one input channel, as listed by Core Audio.
public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    /// The Core Audio device UID: stable across launches and reconnects, so it is what Settings stores.
    public var uid: String
    public var name: String
    /// Input channels (mono); the channel picker offers Input 1 … Input `channelCount`.
    public var channelCount: Int

    public init(uid: String, name: String, channelCount: Int) {
        self.uid = uid
        self.name = name
        self.channelCount = channelCount
    }

    public var id: String { uid }

    /// True for the private aggregate AVAudioEngine can make to join the default input and output.
    /// Its UID holds the app's process ID, so it is gone on the next launch: never list or save it (#20).
    public static func isTemporary(uid: String) -> Bool { uid.hasPrefix("CADefaultDeviceAggregate-") }
}

/// The device and channel the app actually listens to.
public struct AudioInputChoice: Equatable, Sendable {
    public var device: AudioInputDevice
    /// 1-based input channel ("Input 1").
    public var channel: Int
    /// True when a device was saved but isn't connected, so the system default stands in.
    public var isFallback: Bool

    /// The saved device if it is connected, else the system default input (else the first input device).
    /// A channel outside the device's channels becomes Input 1. Nil when there are no input devices.
    public static func resolve(savedUID: String, savedChannel: Int, devices: [AudioInputDevice],
                        defaultUID: String?) -> AudioInputChoice? {
        let saved = devices.first { $0.uid == savedUID }
        guard let device = saved ?? devices.first(where: { $0.uid == defaultUID }) ?? devices.first else {
            return nil
        }
        let channel = (1...max(device.channelCount, 1)).contains(savedChannel) ? savedChannel : 1
        return AudioInputChoice(device: device, channel: channel, isFallback: saved == nil && !savedUID.isEmpty)
    }

    /// "Scarlett 2i2 · Input 1": the input line shown on listening screens.
    public var label: String { "\(device.name) · Input \(channel)" }
}
