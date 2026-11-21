import CoreGraphics

/// How large a dot's label is drawn, or whether its text is drawn at all: drawing rules only.
///
/// The font follows the dot, so labels shrink toward the high frets where the dots get
/// smaller. Never below `minimumFontSize`: if the label can't fit inside the dot even at
/// that size, its text is hidden and the dot stays.
enum FretboardLabelLayout {
    static let minimumFontSize: CGFloat = 8
    static let maximumFontSize: CGFloat = 12

    /// The share of the dot's diameter the text may cover, so it stays clear of the ring.
    static let fillRatio: CGFloat = 0.8

    /// Labels are sized as if at least this wide (a two-character name), so every label on
    /// the same fret gets the same size and they show or hide together, not letter by letter.
    static let referenceLabel = "G♯"

    /// The preferred font size for a dot of this diameter.
    static func preferredFontSize(forDot diameter: CGFloat) -> CGFloat {
        min(maximumFontSize, max(minimumFontSize, diameter * 0.48))
    }

    /// The font size to draw at, or `nil` to hide the text.
    ///
    /// `measure` returns the text's size at a given font size. Text size scales about
    /// linearly with the font, so one measurement at the preferred size decides it.
    static func fontSize(forDot diameter: CGFloat, measure: (CGFloat) -> CGSize) -> CGFloat? {
        let preferred = preferredFontSize(forDot: diameter)
        let size = measure(preferred)
        guard size.width > 0, size.height > 0 else { return preferred }
        let room = diameter * fillRatio
        let fitted = preferred * min(1, room / size.width, room / size.height)
        return fitted >= minimumFontSize ? fitted : nil
    }
}
