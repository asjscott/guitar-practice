import Foundation

extension PitchClass {
    /// The pitch class spelled with sharps: the spelling to use when no key applies.
    /// When a key or scale is known, use key-aware spelling instead (never this).
    public var sharpName: String {
        ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"][value]
    }
}
