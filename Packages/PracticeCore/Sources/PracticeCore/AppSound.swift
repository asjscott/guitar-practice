import TheoryCore

/// A sound the app makes. It lasts exactly `duration`.
public enum AppSound: Hashable, Sendable {
    /// One after another.
    case tones([DrillTone])
    /// Two notes: a block's end is near.
    case chime
    /// The same, softer: a block's planned end.
    case softChime

    public var duration: Duration {
        switch self {
        case .tones(let tones): tones.reduce(.zero) { $0 + $1.duration }
        case .chime, .softChime: .milliseconds(900)
        }
    }
}

/// Tells the app's own sound, heard through a microphone, from the player's notes. Whoever drives a drill keeps one:
/// it tells it what is played, and drops the played notes it ignores before they reach the drill.
public struct AppSoundFilter: Sendable {
    /// How long after a sound ends played notes are still ignored.
    public static let tail: Duration = .milliseconds(300)

    /// How long an ended sound is remembered: longer than a played note takes to be detected.
    private static let memory: Duration = .seconds(5)

    private struct Window {
        let isTones: Bool
        let start: Duration
        let latency: Duration
        var end: Duration
    }

    private var windows: [Window] = []

    public init() {}

    /// A sound was sent to the output, to be heard `latency` later. The wait counts as sound.
    public mutating func started(_ sound: AppSound, at start: Duration, latency: Duration) {
        windows.removeAll { $0.end + Self.memory < start }
        let isTones = if case .tones = sound { true } else { false }
        windows.append(Window(isTones: isTones, start: start, latency: latency, end: start + latency + sound.duration))
    }

    /// The tones were cut off; a chime plays on.
    public mutating func tonesStopped(at time: Duration) {
        for index in windows.indices where windows[index].isTones {
            windows[index].end = min(windows[index].end, time + windows[index].latency)
        }
    }

    /// Whether a played note with this onset may be the app's own sound.
    public func ignores(onset: Duration) -> Bool {
        windows.contains { $0.start <= onset && onset <= $0.end + Self.tail }
    }
}
