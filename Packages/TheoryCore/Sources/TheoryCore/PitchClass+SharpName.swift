import Foundation

extension PitchClass {
    /// The pitch class spelled with sharps: the spelling to use when no key applies.
    /// When a key or scale is known, use key-aware spelling instead (never this).
    public var sharpName: String {
        ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"][value]
    }

    /// True for the seven natural notes C D E F G A B (no sharp or flat needed).
    public var isNatural: Bool {
        [0, 2, 4, 5, 7, 9, 11].contains(value)
    }
}
