import CoreGraphics
import Foundation
import TheoryCore

/// Where things sit when the neck is drawn into a given size: drawing geometry only, no music.
///
/// High string on top, nut on the left. Fret wire n sits at a distance from the nut
/// proportional to 1 − 2^(−n/12) (real-neck spacing), scaled so the last fret reaches the
/// end of the neck at any width. Zoomed in, only some frets are drawn, with everything around them larger.
struct FretboardGeometry {
    // Layout constants
    var nameColumnWidth: CGFloat { isZoomed ? 30 : 22 }                             // string names, left of the open-string area
    var openAreaWidth: CGFloat { frets.contains(0) ? (isZoomed ? 48 : 30) : 0 }     // open strings, left of the nut
    static let rightPadding: CGFloat = 10
    var rulerHeight: CGFloat { isZoomed ? 26 : 20 }                                 // fret numbers under the neck
    /// The bar under the ruler that shows which part of a zoomed neck is drawn.
    static let windowBarHeight: CGFloat = 8
    static let topPadding: CGFloat = 4
    static let bottomPadding: CGFloat = 4

    /// Frets with an inlay; 12 has a double inlay.
    static let inlayFrets: Set<Int> = [3, 5, 7, 9, 12, 15, 17, 19, 21]
    static let doubleInlayFret = 12

    let size: CGSize
    let stringCount: Int
    let lastFret: Int
    /// The frets drawn.
    let frets: ClosedRange<Int>
    let isZoomed: Bool

    init(size: CGSize, diagram: FretboardDiagram) {
        self.size = size
        stringCount = diagram.stringCount
        lastFret = diagram.lastFret
        frets = diagram.frets
        isZoomed = diagram.isZoomed
    }

    /// The wires drawn: the one behind the first fret to the last fret's. Wire 0 is the nut.
    var wires: ClosedRange<Int> { max(frets.lowerBound - 1, 0)...frets.upperBound }

    /// The fingerboard from the first wire drawn to the last.
    var neck: CGRect {
        let x = nameColumnWidth + openAreaWidth
        let barHeight = isZoomed ? Self.windowBarHeight + 4 : 0
        let height = size.height - rulerHeight - barHeight - Self.topPadding - Self.bottomPadding
        return CGRect(x: x, y: Self.topPadding, width: max(size.width - x - Self.rightPadding, 1), height: max(height, 1))
    }

    var rowHeight: CGFloat { neck.height / CGFloat(max(stringCount, 1)) }

    /// Centre line of a string. Index 0 (string 6) is the bottom row, so the high string is on top.
    func y(ofString string: Int) -> CGFloat {
        neck.minY + rowHeight * (CGFloat(stringCount - 1 - string) + 0.5)
    }

    /// x of fret wire n (wire 0 is the nut).
    func wireX(_ n: Int) -> CGFloat {
        neck.minX + neck.width * Self.share(ofWire: n, in: wires)
    }

    /// How far along a stretch of neck a wire is, 0–1.
    private static func share(ofWire n: Int, in wires: ClosedRange<Int>) -> CGFloat {
        func fromNut(_ wire: Int) -> Double { 1 - pow(2, -Double(wire) / 12) }
        let start = fromNut(wires.lowerBound), length = fromNut(wires.upperBound) - start
        return length > 0 ? CGFloat((fromNut(n) - start) / length) : 0
    }

    /// The bar standing for the whole neck, under a zoomed one's ruler.
    var windowBar: CGRect {
        CGRect(x: neck.minX, y: size.height - Self.bottomPadding - Self.windowBarHeight, width: neck.width, height: Self.windowBarHeight)
    }

    /// The part of `windowBar` that is drawn above it.
    var windowBarPart: CGRect {
        let whole = 0...lastFret, bar = windowBar
        let from = Self.share(ofWire: wires.lowerBound, in: whole), to = Self.share(ofWire: wires.upperBound, in: whole)
        return CGRect(x: bar.minX + bar.width * from, y: bar.minY, width: bar.width * (to - from), height: bar.height)
    }

    /// Centre x of the space where a finger presses a fret; fret 0 is the open area before the nut.
    func centerX(ofFret fret: Int) -> CGFloat {
        fret == 0 ? nameColumnWidth + openAreaWidth / 2 : (wireX(fret - 1) + wireX(fret)) / 2
    }

    /// Width of the space for a fret (the open area for fret 0).
    func width(ofFret fret: Int) -> CGFloat {
        fret == 0 ? openAreaWidth : wireX(fret) - wireX(fret - 1)
    }

    /// The whole cell of a fretboard location (useful for tints behind it).
    func cell(at location: FretboardLocation) -> CGRect {
        let x0 = location.fret == 0 ? nameColumnWidth : wireX(location.fret - 1)
        return CGRect(x: x0, y: y(ofString: location.string) - rowHeight / 2,
                      width: width(ofFret: location.fret), height: rowHeight)
    }

    var stringNameX: CGFloat { nameColumnWidth / 2 }

    var rulerY: CGFloat { neck.maxY + rulerHeight / 2 + 2 }

    /// Dot diameter at a fret: as large as the row allows, never smaller than 11 pt.
    func dotDiameter(atFret fret: Int) -> CGFloat {
        min(rowHeight * 0.78, max(width(ofFret: fret) * 0.66, 11))
    }
}
