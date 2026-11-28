import SwiftUI
import TheoryCore

/// Draws a realistic neck, or the frets of it that the diagram zooms in on, and the markers of a `FretboardDiagram`.
///
/// High string on top, nut on the left, real-neck fret spacing to the last fret, wood board,
/// bone nut, wound bass strings thinning to string 1, pearl inlays, string names and a fret
/// ruler. The view fills whatever width it is given.
///
/// Drawing happens in passes, back to front (see `draw`). New features add a pass
/// (for example a capo bar over the strings). The heatmap tint is the pass right after the
/// fingerboard, under the inlays.
struct FretboardView: View {
    let diagram: FretboardDiagram
    var minHeight: CGFloat = 200

    var body: some View {
        Canvas { context, size in
            let geometry = FretboardGeometry(size: size, diagram: diagram)
            draw(in: &context, geometry)
        }
        .frame(minHeight: minHeight)
        .accessibilityElement()
        .accessibilityLabel("Fretboard")
    }

    private func draw(in context: inout GraphicsContext, _ geometry: FretboardGeometry) {
        drawFingerboard(in: &context, geometry)
        drawHeat(in: &context, geometry)
        drawInlays(in: &context, geometry)
        drawFretWires(in: &context, geometry)
        drawNut(in: &context, geometry)
        drawStrings(in: &context, geometry)
        drawCapo(in: &context, geometry)
        drawStringHighlight(in: &context, geometry)
        drawStringNames(in: &context, geometry)
        drawFretRuler(in: &context, geometry)
        drawWindowBar(in: &context, geometry)
        drawMarkers(in: &context, geometry)
    }

    // MARK: Passes

    private func drawFingerboard(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        let neck = g.neck
        context.fill(
            Path(roundedRect: neck, cornerRadius: 3),
            with: .linearGradient(
                Gradient(colors: [FretboardPalette.woodTop, FretboardPalette.woodBottom]),
                startPoint: CGPoint(x: 0, y: neck.minY), endPoint: CGPoint(x: 0, y: neck.maxY)))
        for edge in [neck.minY + 0.75, neck.maxY - 0.75] {
            context.stroke(line(from: CGPoint(x: neck.minX, y: edge), to: CGPoint(x: neck.maxX, y: edge)),
                           with: .color(FretboardPalette.binding.opacity(0.9)), lineWidth: 1.5)
        }
    }

    /// Heatmap tint: one rounded cell per location the diagram gives a value for, behind
    /// everything that sits on the board. Off when `diagram.heat` is nil.
    private func drawHeat(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        guard let heat = diagram.heat else { return }
        for (location, value) in heat where diagram.draws(location) {
            let cell = g.cell(at: location).insetBy(dx: 1, dy: 1)
            context.fill(Path(roundedRect: cell, cornerRadius: 3), with: .color(FretboardPalette.heat(value)))
        }
    }

    private func drawInlays(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        func inlay(_ fret: Int, _ centerY: CGFloat) {
            let d = max(5, min(g.isZoomed ? 14 : 8, g.width(ofFret: fret) * 0.26))
            let rect = CGRect(x: g.centerX(ofFret: fret) - d / 2, y: centerY - d / 2, width: d, height: d)
            context.fill(Path(ellipseIn: rect), with: .color(FretboardPalette.pearl.opacity(0.85)))
        }
        for fret in FretboardGeometry.inlayFrets where diagram.frets.contains(fret) {
            if fret == FretboardGeometry.doubleInlayFret, diagram.stringCount >= 4 {
                // Between the second and third strings from each edge.
                inlay(fret, g.neck.minY + g.rowHeight * 2)
                inlay(fret, g.neck.maxY - g.rowHeight * 2)
            } else {
                inlay(fret, g.neck.midY)
            }
        }
    }

    private func drawFretWires(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        for n in g.wires where n > 0 {
            let x = g.wireX(n)
            context.stroke(line(from: CGPoint(x: x, y: g.neck.minY), to: CGPoint(x: x, y: g.neck.maxY)),
                           with: .color(.black.opacity(0.35)), lineWidth: 1)
            context.stroke(line(from: CGPoint(x: x - 1, y: g.neck.minY), to: CGPoint(x: x - 1, y: g.neck.maxY)),
                           with: .color(FretboardPalette.fretWire), lineWidth: 1.6)
        }
    }

    private func drawNut(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        guard g.wires.contains(0) else { return }
        let nut = CGRect(x: g.neck.minX - 3, y: g.neck.minY - 1, width: 6, height: g.neck.height + 2)
        context.fill(Path(roundedRect: nut, cornerRadius: 1.5), with: .color(FretboardPalette.bone))
    }

    /// Thicker, wound strings toward string 6; thin plain strings toward string 1.
    private func drawStrings(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        let count = diagram.stringCount
        let startX = min(g.nameColumnWidth + 4, g.neck.minX)
        for string in 0..<count {
            let scale = g.isZoomed ? 1.4 : 1
            let width = scale * (2.5 - 1.6 * CGFloat(string) / CGFloat(max(count - 1, 1))) // unzoomed, ≈2.5 pt down to ≈0.9 pt
            let isWound = string < count / 2
            let y = g.y(ofString: string)
            context.stroke(line(from: CGPoint(x: startX, y: y + 1), to: CGPoint(x: g.neck.maxX, y: y + 1)),
                           with: .color(.black.opacity(0.35)), lineWidth: width)
            context.stroke(line(from: CGPoint(x: startX, y: y), to: CGPoint(x: g.neck.maxX, y: y)),
                           with: .color(isWound ? FretboardPalette.woundString : FretboardPalette.plainString),
                           lineWidth: width)
        }
    }

    /// Dims the nut and the frets below the capo, then draws the bar just behind the capo fret, where those are drawn.
    private func drawCapo(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        let capo = diagram.capo
        guard capo > 0, capo <= diagram.lastFret else { return }
        guard capo > g.wires.lowerBound else { return }
        let isDrawn = capo <= g.wires.upperBound
        let x = isDrawn ? g.wireX(capo - 1) : g.neck.maxX
        let left = g.neck.minX - (g.wires.contains(0) ? 3 : 0)
        let dimmed = CGRect(x: left, y: g.neck.minY - 1, width: x - left, height: g.neck.height + 2)
        context.fill(Path(dimmed), with: .color(.black.opacity(0.55)))
        guard isDrawn else { return }
        let bar = CGRect(x: x - 6, y: g.neck.minY - 6, width: 10, height: g.neck.height + 12)
        context.fill(Path(roundedRect: bar, cornerRadius: 4),
                     with: .linearGradient(Gradient(colors: [FretboardPalette.capoLight, FretboardPalette.capoDark]),
                                           startPoint: CGPoint(x: bar.minX, y: 0), endPoint: CGPoint(x: bar.maxX, y: 0)))
    }

    /// A soft yellow band along each of `diagram.highlightedStrings`, from its name to the end of the neck,
    /// over the strings and capo but under the markers.
    private func drawStringHighlight(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        for string in diagram.highlightedStrings where (0..<diagram.stringCount).contains(string) {
            let height = g.rowHeight * 0.9
            let band = CGRect(x: 0, y: g.y(ofString: string) - height / 2, width: g.neck.maxX, height: height)
            context.fill(Path(roundedRect: band, cornerRadius: 3), with: .color(FretboardPalette.stringHighlight))
        }
    }

    private func drawStringNames(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        for (string, name) in diagram.stringNames.enumerated() {
            context.draw(Text(name).font(.system(size: g.isZoomed ? 15 : 11, weight: .medium)).foregroundColor(.secondary),
                         at: CGPoint(x: g.stringNameX, y: g.y(ofString: string)))
        }
    }

    private func drawFretRuler(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        for fret in diagram.frets where fret > 0 {
            let marked = FretboardGeometry.inlayFrets.contains(fret)
            let text = Text("\(fret)")
                .font(.system(size: g.isZoomed ? 14 : 9, weight: marked ? .semibold : .regular).monospacedDigit())
                .foregroundColor(marked ? .secondary : Color.secondary.opacity(0.45))
            context.draw(text, at: CGPoint(x: g.centerX(ofFret: fret), y: g.rulerY))
        }
    }

    /// Which part of the neck a zoomed one is.
    private func drawWindowBar(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        guard g.isZoomed else { return }
        func bar(_ rect: CGRect) -> Path { Path(roundedRect: rect, cornerRadius: rect.height / 2) }
        context.fill(bar(g.windowBar), with: .color(.secondary.opacity(0.2)))
        context.fill(bar(g.windowBarPart), with: .color(FretboardPalette.woundString))
    }

    /// Dots (root orange, tones blue) with a soft shadow, then the white ring and label on top. Faint ones have neither
    /// shadow nor label; the last note played has a yellow ring as well.
    private func drawMarkers(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        let markers = diagram.markers.filter { diagram.draws($0.location) }
        func dotRect(_ marker: FretboardDiagram.Marker) -> CGRect {
            let d = g.dotDiameter(atFret: marker.location.fret)
            let center = CGPoint(x: g.centerX(ofFret: marker.location.fret), y: g.y(ofString: marker.location.string))
            return CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
        }

        var shadowed = context
        shadowed.addFilter(.shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1))
        for marker in markers {
            let color = FretboardPalette.color(for: marker.role)
            if marker.isFaint {
                context.fill(Path(ellipseIn: dotRect(marker)), with: .color(color.opacity(0.35 * marker.opacity)))
            } else {
                var shadowed = shadowed
                shadowed.opacity = marker.opacity
                shadowed.fill(Path(ellipseIn: dotRect(marker)), with: .color(color))
            }
        }
        for marker in markers {
            let rect = dotRect(marker)
            var context = context
            context.opacity = marker.opacity
            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(marker.isFaint ? 0.3 : 0.85)), lineWidth: 1.25)
            if marker.isLastPlayed {
                context.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(FretboardPalette.lastPlayedRing),
                               lineWidth: g.isZoomed ? 4 : 2.5)
            }
            if !marker.isFaint { drawLabel(marker.label, in: rect, context: &context) }
        }
    }

    /// The label inside a dot, per `diagram.labelMode`: shown, faded (about 30%) or hidden.
    /// The font shrinks with the dot (see `FretboardLabelLayout`); text that can't fit is hidden.
    private func drawLabel(_ label: String, in dot: CGRect, context: inout GraphicsContext) {
        let opacity: Double
        switch diagram.labelMode {
        case .shown: opacity = 1
        case .faded: opacity = 0.3
        case .hidden: return
        }
        func text(_ string: String, _ size: CGFloat) -> Text {
            Text(string).font(.system(size: size, weight: .semibold, design: .rounded))
        }
        let unbounded = CGSize(width: CGFloat.infinity, height: .infinity)
        func measure(_ size: CGFloat) -> CGSize {
            let own = context.resolve(text(label, size)).measure(in: unbounded)
            let reference = context.resolve(text(FretboardLabelLayout.referenceLabel, size)).measure(in: unbounded)
            return CGSize(width: max(own.width, reference.width), height: max(own.height, reference.height))
        }
        guard let fontSize = FretboardLabelLayout.fontSize(forDot: dot.width, isZoomed: diagram.isZoomed, measure: measure)
        else { return } // no room for text: the dot alone stays
        context.draw(text(label, fontSize).foregroundColor(.white.opacity(opacity)), at: CGPoint(x: dot.midX, y: dot.midY))
    }

    private func line(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}

#Preview {
    FretboardView(diagram: FretboardDiagram(
        stringNames: ["E", "A", "D", "G", "B", "E"],
        markers: [
            .init(location: FretboardLocation(string: 0, fret: 8), label: "C", role: .root),
            .init(location: FretboardLocation(string: 1, fret: 10), label: "G", role: .tone),
            .init(location: FretboardLocation(string: 5, fret: 20), label: "C", role: .root),
        ]))
        .frame(width: 900, height: 250)
        .padding()
}
