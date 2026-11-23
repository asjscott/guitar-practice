import Foundation

// Pure audio-input logic: no AVFoundation, no Core Audio, so it can be checked without hardware.

/// An audio device with at least one input channel, as listed by Core Audio.
struct AudioInputDevice: Identifiable, Hashable, Sendable {
    /// The Core Audio device UID: stable across launches and reconnects, so it is what Settings stores.
    var uid: String
    var name: String
    /// Input channels (mono); the channel picker offers Input 1 … Input `channelCount`.
    var channelCount: Int

    var id: String { uid }

    /// True for the private aggregate AVAudioEngine can make to join the default input and output.
    /// Its UID holds the app's process ID, so it is gone on the next launch: never list or save it (#20).
    static func isTemporary(uid: String) -> Bool { uid.hasPrefix("CADefaultDeviceAggregate-") }
}

/// The device and channel the app actually listens to.
struct AudioInputChoice: Equatable, Sendable {
    var device: AudioInputDevice
    /// 1-based input channel ("Input 1").
    var channel: Int
    /// True when a device was saved but isn't connected, so the system default stands in.
    var isFallback: Bool

    /// The saved device if it is connected, else the system default input (else the first input device).
    /// A channel outside the device's channels becomes Input 1. Nil when there are no input devices.
    static func resolve(savedUID: String, savedChannel: Int, devices: [AudioInputDevice],
                        defaultUID: String?) -> AudioInputChoice? {
        let saved = devices.first { $0.uid == savedUID }
        guard let device = saved ?? devices.first(where: { $0.uid == defaultUID }) ?? devices.first else {
            return nil
        }
        let channel = (1...max(device.channelCount, 1)).contains(savedChannel) ? savedChannel : 1
        return AudioInputChoice(device: device, channel: channel, isFallback: saved == nil && !savedUID.isEmpty)
    }

    /// "Scarlett 2i2 · Input 1": the input line shown on listening screens.
    var label: String { "\(device.name) · Input \(channel)" }
}

/// Maps input level to the input meter: −60 dBFS (and quieter) is empty, 0 dBFS is full, linear in dB between.
enum InputMeterScale {
    static let floorDBFS = -60.0

    /// 0–1 meter fraction for a level in dBFS.
    static func fraction(dBFS: Double) -> Double {
        min(max((dBFS - floorDBFS) / -floorDBFS, 0), 1)
    }

    /// The block's peak in dBFS; silence or an empty block gives −∞.
    static func peakDBFS(_ samples: UnsafeBufferPointer<Float>) -> Double {
        var peak: Float = 0
        for sample in samples { peak = max(peak, abs(sample)) }
        return 20 * log10(Double(peak))
    }
}
