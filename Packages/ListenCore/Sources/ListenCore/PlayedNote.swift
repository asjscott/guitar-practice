import Foundation

/// A pitch the listener heard held steadily, close enough to an equal-tempered
/// pitch (A4 = 440 Hz) to count. One pluck gives at most one played note.
public struct PlayedNote: Sendable, Equatable {
    /// The equal-tempered pitch as a MIDI note number (middle C = 60).
    public let midiNote: Int
    /// Cents from `midiNote`, within ±`maximumCents`. Unsmoothed.
    public let cents: Double
    /// When the note started sounding, in stream seconds (the `time` passed to
    /// `Listener.process`): the onset, before the listener was sure of the note.
    public let onset: Double

    /// How long a pitch must hold steady to count, in seconds.
    public static let stability = 0.08
    /// How far from equal temperament a played note may be, in cents.
    public static let maximumCents = 30.0
}
