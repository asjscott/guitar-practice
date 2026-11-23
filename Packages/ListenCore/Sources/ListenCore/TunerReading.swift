import Foundation

/// What a tuner shows: the nearest equal-tempered pitch (A4 = 440 Hz),
/// how far the sound is from it, and its frequency. Smoothed enough to tune by.
public struct TunerReading: Sendable, Equatable {
    /// Nearest equal-tempered pitch as a MIDI note number (middle C = 60).
    public let midiNote: Int
    /// Cents from `midiNote`, −50…+50.
    public let cents: Double
    /// Frequency in Hz.
    public let frequency: Double

    /// Width of the "in tune" band either side of the pitch, in cents.
    public static let inTuneCents = 5.0

    /// True within ±5 cents of the pitch.
    public var isInTune: Bool { abs(cents) <= Self.inTuneCents }

    /// The reading for a frequency in Hz.
    public init(frequency: Double) {
        let exact = 69 + 12 * log2(frequency / 440)
        let nearest = exact.rounded()
        self.midiNote = Int(nearest)
        self.cents = (exact - nearest) * 100
        self.frequency = frequency
    }
}
