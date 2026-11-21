import Foundation

/// The five CAGED shapes, in order up the neck from the E shape (Position 1–5).
///
/// Each is named by the major-pentatonic degree that starts it on string 6 (ADR-0001):
/// 1 → E, 2 → D, 3 → C, 5 → A, 6 → G.
public enum CAGEDShape: String, Hashable, Sendable, Codable, CaseIterable {
    case e, d, c, a, g

    /// Position number 1–5: the name used where CAGED names don't apply.
    public var number: Int { Self.allCases.firstIndex(of: self)! + 1 }

    /// "E", "D", "C", "A", "G".
    public var letter: String { rawValue.uppercased() }

    /// The major-pentatonic degree the shape starts on, on string 6.
    public var startingDegree: Int { [1, 2, 3, 5, 6][number - 1] }

    /// The shape for a position number 1–5.
    public init?(number: Int) {
        guard (1...5).contains(number) else { return nil }
        self = Self.allCases[number - 1]
    }
}
