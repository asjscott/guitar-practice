import Foundation

/// Three adjacent strings a triad is played on (see "String set" in GLOSSARY.md).
///
/// Named by the open notes of those strings in standard tuning, whatever the actual tuning.
public struct StringSet: Hashable, Sendable, Codable, CaseIterable {
    /// The internal index of the set's lowest string (0 = physical string 6).
    public let lowestString: Int

    public init(lowestString: Int) {
        precondition(lowestString >= 0, "String indices start at 0")
        self.lowestString = lowestString
    }

    public static let eAD = StringSet(lowestString: 0)
    public static let aDG = StringSet(lowestString: 1)
    public static let dGB = StringSet(lowestString: 2)
    public static let gBE = StringSet(lowestString: 3)

    /// The four string sets of a six-string guitar, lowest first.
    public static let allCases: [StringSet] = [.eAD, .aDG, .dGB, .gBE]

    /// The set's string indices, lowest string first.
    public var strings: ClosedRange<Int> { lowestString...(lowestString + 2) }

    /// For example "E-A-D": the strings' open notes in standard tuning.
    public var name: String {
        let standard = ["E", "A", "D", "G", "B", "E"]
        guard strings.upperBound < standard.count else {
            return strings.map { "\($0)" }.joined(separator: "-")
        }
        return strings.map { standard[$0] }.joined(separator: "-")
    }
}

extension StringSet: CustomStringConvertible {
    public var description: String { name }
}
