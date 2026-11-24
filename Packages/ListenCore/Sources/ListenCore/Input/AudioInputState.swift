/// The player's answer to the microphone prompt.
public enum AudioInputPermission: Equatable, Sendable {
    case undetermined, granted, denied
}

/// What a listening screen needs to know of the audio input: why nothing can be heard, and when an input is lost.
public struct AudioInputState: Equatable, Sendable {
    public var permission: AudioInputPermission
    /// The device being listened to; nil when there is none.
    public var device: AudioInputDevice?
    /// Every input device there is.
    public var devices: [AudioInputDevice]
    public var isRunning: Bool

    public init(permission: AudioInputPermission, device: AudioInputDevice?, devices: [AudioInputDevice], isRunning: Bool) {
        self.permission = permission
        self.device = device
        self.devices = devices
        self.isRunning = isRunning
    }

    /// Why nothing can be heard, so that a listening exercise shouldn't start or resume; nil when it can.
    public var problem: AudioInputProblem? {
        switch permission {
        case .denied: .noAccess
        case .undetermined: .accessNotGiven
        case .granted: device == nil ? .noInput : nil
        }
    }

    /// Says how the input was lost since `old`, if it was. Choosing another input in Settings doesn't lose one.
    public func lossNotice(after old: AudioInputState) -> String? {
        if permission != .granted, old.permission == .granted { return "Microphone access was turned off." }
        if let lost = old.device, !devices.contains(where: { $0.uid == lost.uid }) { return "\(lost.name) was disconnected." }
        return old.isRunning && !isRunning ? "The audio input stopped." : nil
    }
}

/// Why nothing can be heard.
public enum AudioInputProblem: Equatable, Sendable {
    /// The player hasn't answered yet.
    case accessNotGiven
    case noAccess, noInput

    public var text: String {
        switch self {
        case .accessNotGiven: "Waiting for microphone access"
        case .noAccess: "Microphone access is off"
        case .noInput: "No input device"
        }
    }
}
