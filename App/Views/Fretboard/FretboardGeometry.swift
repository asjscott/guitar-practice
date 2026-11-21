import CoreGraphics
import Foundation
import TheoryCore

/// Where things sit when the neck is drawn into a given size: drawing geometry only, no music.
///
/// High string on top, nut on the left. Fret wire n sits at a distance from the nut
/// proportional to 1 − 2^(−n/12) (real-neck spacing), scaled so the last fret reaches the
/// end of the neck at any width.
struct FretboardGeometry {
    // Layout constants
    static let nameColumnWidth: CGFloat = 22   // string names, left of the open-string area
    static let openAreaWidth: CGFloat = 30     // open strings, left of the nut
    static let rightPadding: CGFloat = 10
    static let rulerHeight: CGFloat = 20       // fret numbers under the neck
    static let topPadding: CGFloat = 4
    static let bottomPadding: CGFloat = 4

    /// Frets with an inlay; 12 has a double inlay.
    static let inlayFrets: Set<Int> = [3, 5, 7, 9, 12, 15, 17, 19, 21]
    static let doubleInlayFret = 12

    let size: CGSize
    let stringCount: Int
    let lastFret: Int

    /// The fingerboard from the nut to the last fret.
    var neck: CGRect {
        let x = Self.nameColumnWidth + Self.openAreaWidth
        let height = size.height - Self.rulerHeight - Self.topPadding - Self.bottomPadding
        return CGRect(x: x, y: Self.topPadding, width: max(size.width - x - Self.rightPadding, 1), height: max(height, 1))
    }

    var nutX: CGFloat { neck.minX }

    var rowHeight: CGFloat { neck.height / CGFloat(max(stringCount, 1)) }

    /// Centre line of a string. Index 0 (string 6) is the bottom row, so the high string is on top.
    func y(ofString string: Int) -> CGFloat {
        neck.minY + rowHeight * (CGFloat(stringCount - 1 - string) + 0.5)
    }

    /// x of fret wire n (wire 0 is the nut).
    func wireX(_ n: Int) -> CGFloat {
        let full = 1 - pow(2, -Double(lastFret) / 12)
        return neck.minX + neck.width * CGFloat((1 - pow(2, -Double(n) / 12)) / full)
    }

    /// Centre x of the space where a finger presses a fret; fret 0 is the open area before the nut.
    func centerX(ofFret fret: Int) -> CGFloat {
        fret == 0 ? Self.nameColumnWidth + Self.openAreaWidth / 2 : (wireX(fret - 1) + wireX(fret)) / 2
    }

    /// Width of the space for a fret (the open area for fret 0).
    func width(ofFret fret: Int) -> CGFloat {
        fret == 0 ? Self.openAreaWidth : wireX(fret) - wireX(fret - 1)
    }

    /// The whole cell of a fretboard location (useful for tints behind it).
    func cell(at location: FretboardLocation) -> CGRect {
        let x0 = location.fret == 0 ? Self.nameColumnWidth : wireX(location.fret - 1)
        return CGRect(x: x0, y: y(ofString: location.string) - rowHeight / 2,
                      width: width(ofFret: location.fret), height: rowHeight)
    }

    var stringNameX: CGFloat { Self.nameColumnWidth / 2 }

    var rulerY: CGFloat { neck.maxY + Self.rulerHeight / 2 + 2 }

    /// Dot diameter at a fret: as large as the row allows, never smaller than 11 pt.
    func dotDiameter(atFret fret: Int) -> CGFloat {
        min(rowHeight * 0.78, max(width(ofFret: fret) * 0.66, 11))
    }
}
