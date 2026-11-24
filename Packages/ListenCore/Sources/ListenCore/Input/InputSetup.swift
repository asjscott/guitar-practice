/// The device and format an input unit listens to: compared to tell a real change from a repeat notice.
public struct InputSetup: Equatable, Sendable {
    /// The Core Audio device ID; changes when the device reconnects.
    public var deviceID: UInt32
    /// Hz; 0 if the device has none.
    public var sampleRate: Double
    public var channelCount: Int

    public init(deviceID: UInt32, sampleRate: Double, channelCount: Int) {
        self.deviceID = deviceID
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    /// False while a device is still changing over, or has no input.
    public var canStart: Bool { channelCount > 0 && sampleRate > 0 }

    /// Whether to start again after a notice, given the set-up tried last (nil when stopped) and the one there now.
    /// Only a real change counts, so a notice caused by starting doesn't restart forever (#20).
    public static func needsRestart(tried: InputSetup?, now: InputSetup) -> Bool {
        tried != nil && tried != now
    }
}
