/// How far a subject has got towards being played from its roots alone (ADR 0007). A prompt's notes start fully shown
/// and fade out by its fade time, a share of its expected time that each level shortens; the roots stay marked. Level
/// 0 never fades, and at the last only the roots are shown from the start.
public struct FadeLevel: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// 0–6.
    public let number: Int

    /// Kept within 0–6.
    public init(_ number: Int) {
        self.number = min(max(number, 0), Self.shares.count - 1)
    }

    /// What an old fade stage reads as: Shown 0, Faded 2, Hidden the last.
    public init(_ stage: FadeStage) {
        switch stage {
        case .shown: self = .first
        case .faded: self.init(2)
        case .hidden: self = .last
        }
    }

    public static let first = FadeLevel(0)
    public static let last = FadeLevel(shares.count - 1)
    public static let all = (0..<shares.count).map(FadeLevel.init)

    /// The share of the expected time each level fades by, in per cent; nil never fades.
    private static let shares: [Int?] = [nil, 90, 68, 51, 38, 28, 0]

    /// How long a prompt's notes stay on screen, from an expected time: nil never fades, zero shows only the roots.
    public func fadeTime(expected: Duration) -> Duration? {
        Self.shares[number].map { expected * $0 / 100 }
    }

    public static func < (lhs: FadeLevel, rhs: FadeLevel) -> Bool { lhs.number < rhs.number }

    /// "Level 2".
    public var description: String { "Level \(number)" }
}

/// How one note of a prompt that isn't a root fades: fully shown until the prompt starts, then linearly to nothing by
/// the fade time.
public struct NoteFade: Hashable, Sendable {
    public let start: Duration
    /// Nil never fades.
    public let fadeTime: Duration?

    public init(level: FadeLevel, expected: Duration, start: Duration) {
        self.start = start
        fadeTime = level.fadeTime(expected: expected)
    }

    /// The fade that shows a note the whole time.
    public static let none = NoteFade(level: .first, expected: .zero, start: .zero)

    /// From 1 (fully shown) to 0 (gone).
    public func opacity(at now: Duration) -> Double {
        guard let fadeTime else { return 1 }
        guard fadeTime > .zero else { return 0 }
        return min(1, max(0, 1 - (now - start) / fadeTime))
    }
}
