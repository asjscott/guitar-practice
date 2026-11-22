import TheoryCore

/// The Note → play it drill's options, chosen before a run and fixed while it goes.
public struct NotePlayItOptions: Hashable, Sendable {
    /// Which notes the drill prompts.
    public enum Notes: Hashable, Sendable {
        /// C D E F G A B only.
        case naturals
        /// All twelve, spelled with sharps.
        case all
    }

    /// The order of prompts.
    public enum Order: Hashable, Sendable {
        /// Random, never the same prompt twice in a row.
        case random
        /// "In order (check)": every location in range once, string 6 first, fret by fret.
        case inOrder
    }

    /// The two fret ranges offered in the toolbar.
    public static let fretRanges: [ClosedRange<Int>] = [0...12, 0...22]

    public var notes: Notes = .naturals

    /// Frets counted from the nut. Frets below the capo are never prompted.
    public var frets: ClosedRange<Int> = 0...12

    /// Included strings as internal indices (0 = string 6); nil = every string.
    public var strings: Set<Int>? = nil

    public var order: Order = .random

    public init() {}
}
