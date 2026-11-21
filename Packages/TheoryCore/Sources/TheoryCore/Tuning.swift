import Foundation

/// The open pitch of each string in physical order, string 6 (the low string) first.
///
/// Any string count is allowed, and pitches need not rise from string to string
/// (re-entrant tunings). String index 0 is physical string 6; UI labels use
/// `stringNumber(ofString:)` for the guitarist's numbering.
public struct Tuning: Hashable, Sendable, Codable {
    public let openPitches: [Pitch]

    public init(_ openPitches: [Pitch]) {
        precondition(!openPitches.isEmpty, "A tuning needs at least one string")
        self.openPitches = openPitches
    }

    /// E2 A2 D3 G3 B3 E4.
    public static let standard = Tuning([40, 45, 50, 55, 59, 64].map(Pitch.init))

    public var stringCount: Int { openPitches.count }

    /// String indices, 0 = physical string 6.
    public var strings: Range<Int> { openPitches.indices }

    public func openPitch(ofString string: Int) -> Pitch { openPitches[string] }

    /// Guitarist's string number for an internal string index: index 0 is string 6 on a
    /// 6-string (the highest number), the last index is string 1.
    public func stringNumber(ofString string: Int) -> Int { stringCount - string }
}
