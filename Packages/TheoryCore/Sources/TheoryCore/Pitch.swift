import Foundation

/// A specific sounding note, octave included: a MIDI note number (middle C = 60 = C4).
public struct Pitch: Hashable, Comparable, Sendable, Codable {
    public let midi: Int

    public init(_ midi: Int) {
        self.midi = midi
    }

    /// The pitch with its octave ignored.
    public var pitchClass: PitchClass { PitchClass(midi) }

    /// Scientific octave number: middle C (60) is in octave 4, MIDI 0 in octave −1.
    public var octave: Int { Int((Double(midi) / 12).rounded(.down)) - 1 }

    public static func < (lhs: Pitch, rhs: Pitch) -> Bool { lhs.midi < rhs.midi }
    public static func + (lhs: Pitch, rhs: Interval) -> Pitch { Pitch(lhs.midi + rhs.semitones) }
    public static func - (lhs: Pitch, rhs: Interval) -> Pitch { Pitch(lhs.midi - rhs.semitones) }
    /// The interval from `rhs` up to `lhs`.
    public static func - (lhs: Pitch, rhs: Pitch) -> Interval { Interval(lhs.midi - rhs.midi) }
}

extension Pitch: CustomStringConvertible {
    public var description: String { "\(pitchClass.sharpName)\(octave)" }
}

/// A note name with octave ignored: 0–11, C = 0. Any `Int` wraps into that range.
public struct PitchClass: Hashable, Sendable, Codable, CaseIterable {
    public let value: Int

    public init(_ value: Int) {
        self.value = ((value % 12) + 12) % 12
    }

    /// C, C♯, D … B in ascending order.
    public static let allCases: [PitchClass] = (0..<12).map(PitchClass.init)

    public static func + (lhs: PitchClass, rhs: Interval) -> PitchClass { PitchClass(lhs.value + rhs.semitones) }
    public static func - (lhs: PitchClass, rhs: Interval) -> PitchClass { PitchClass(lhs.value - rhs.semitones) }

    /// The interval (0–11 semitones) going up from this pitch class to `other`.
    public func interval(upTo other: PitchClass) -> Interval {
        Interval(PitchClass(other.value - value).value)
    }
}

extension PitchClass: CustomStringConvertible {
    public var description: String { sharpName }
}
