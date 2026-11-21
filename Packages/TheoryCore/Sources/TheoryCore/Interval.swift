import Foundation

/// A distance between two pitches, in semitones. May be negative (downwards).
public struct Interval: Hashable, Comparable, Sendable, Codable {
    public let semitones: Int

    public init(_ semitones: Int) {
        self.semitones = semitones
    }

    public static let unison = Interval(0)
    public static let octave = Interval(12)

    public static func < (lhs: Interval, rhs: Interval) -> Bool { lhs.semitones < rhs.semitones }
    public static func + (lhs: Interval, rhs: Interval) -> Interval { Interval(lhs.semitones + rhs.semitones) }
    public static func - (lhs: Interval, rhs: Interval) -> Interval { Interval(lhs.semitones - rhs.semitones) }
}

extension Interval: CustomStringConvertible {
    public var description: String { "\(semitones) st" }
}
