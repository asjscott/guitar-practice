import Foundation

/// Three adjacent strings a triad is played on (see "String set" in GLOSSARY.md).
///
/// The four sets of a six-string neck, named by the open notes of those strings in standard
/// tuning, whatever the actual tuning. This is the one list of string sets: a fretboard offers
/// the ones its tuning has strings for (`Fretboard.stringSets`).
public enum StringSet: String, Hashable, Sendable, Codable, CaseIterable {
    case eAD, aDG, dGB, gBE

    /// The internal index of the set's lowest string (0 = physical string 6).
    public var lowestString: Int { Self.allCases.firstIndex(of: self)! }

    /// The set's string indices, lowest string first.
    public var strings: ClosedRange<Int> { lowestString...(lowestString + 2) }

    /// The string a voicing's note is on (0 = its lowest).
    public func string(ofNote index: Int) -> Int { Array(strings)[index] }

    /// For example "E-A-D": the strings' open notes in standard tuning.
    public var name: String {
        switch self {
        case .eAD: "E-A-D"
        case .aDG: "A-D-G"
        case .dGB: "D-G-B"
        case .gBE: "G-B-E"
        }
    }
}

extension StringSet: CustomStringConvertible {
    public var description: String { name }
}
