#if DEBUG
import AppKit

/// Screens gathered nine to a page, each with its name, so that many can be looked at in one image.
@MainActor
struct ContactSheet {
    private var screens: [(name: String, image: NSBitmapImageRep)] = []

    private static let columns = 3
    private static let perPage = 9
    private static let cell = CGSize(width: 620, height: 400)
    private static let labelHeight = 24.0

    mutating func add(_ name: String, _ image: NSBitmapImageRep) { screens.append((name, image)) }

    /// A PNG per page.
    func pages() -> [Data] {
        stride(from: 0, to: screens.count, by: Self.perPage).compactMap { start in
            Self.page(Array(screens[start..<min(start + Self.perPage, screens.count)]))
        }
    }

    private static func page(_ screens: [(name: String, image: NSBitmapImageRep)]) -> Data? {
        let columns = min(Self.columns, screens.count)
        let rows = (screens.count + columns - 1) / columns
        let size = CGSize(width: cell.width * Double(columns), height: cell.height * Double(rows))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        NSColor.gray.setFill()
        CGRect(origin: .zero, size: size).fill()

        for (index, screen) in screens.enumerated() {
            // Rows fill from the top; the context's origin is at the bottom.
            let origin = CGPoint(x: Double(index % columns) * cell.width,
                                 y: size.height - Double(index / columns + 1) * cell.height)
            (screen.name as NSString).draw(at: CGPoint(x: origin.x + 8, y: origin.y + cell.height - labelHeight + 3), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.white,
            ])
            let room = CGSize(width: cell.width - 16, height: cell.height - labelHeight - 8)
            let scale = min(room.width / screen.image.size.width, room.height / screen.image.size.height)
            let drawn = CGSize(width: screen.image.size.width * scale, height: screen.image.size.height * scale)
            screen.image.draw(in: CGRect(x: origin.x + 8, y: origin.y + 8 + room.height - drawn.height,
                                         width: drawn.width, height: drawn.height))
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif
