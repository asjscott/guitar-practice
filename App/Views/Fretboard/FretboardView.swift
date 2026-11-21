import SwiftUI
import TheoryCore

/// Draws a realistic neck and the markers of a `FretboardDiagram`.
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

    var body: some View {
        Canvas { context, size in
            let geometry = FretboardGeometry(size: size, stringCount: diagram.stringCount, lastFret: diagram.lastFret)
            draw(in: &context, geometry)
        }
        .frame(minHeight: 200)
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
        drawStringNames(in: &context, geometry)
        drawFretRuler(in: &context, geometry)
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
        for (location, value) in heat
        where (0..<diagram.stringCount).contains(location.string) && (0...diagram.lastFret).contains(location.fret) {
            let cell = g.cell(string: location.string, fret: location.fret).insetBy(dx: 1, dy: 1)
            context.fill(Path(roundedRect: cell, cornerRadius: 3), with: .color(FretboardPalette.heat(value)))
        }
    }

    private func drawInlays(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        func inlay(_ fret: Int, _ centerY: CGFloat) {
            let d = max(5, min(8, g.width(ofFret: fret) * 0.26))
            let rect = CGRect(x: g.centerX(ofFret: fret) - d / 2, y: centerY - d / 2, width: d, height: d)
            context.fill(Path(ellipseIn: rect), with: .color(FretboardPalette.pearl.opacity(0.85)))
        }
        for fret in FretboardGeometry.inlayFrets where fret <= diagram.lastFret {
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
        guard diagram.lastFret >= 1 else { return }
        for n in 1...diagram.lastFret {
            let x = g.wireX(n)
            context.stroke(line(from: CGPoint(x: x, y: g.neck.minY), to: CGPoint(x: x, y: g.neck.maxY)),
                           with: .color(.black.opacity(0.35)), lineWidth: 1)
            context.stroke(line(from: CGPoint(x: x - 1, y: g.neck.minY), to: CGPoint(x: x - 1, y: g.neck.maxY)),
                           with: .color(FretboardPalette.fretWire), lineWidth: 1.6)
        }
    }

    private func drawNut(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        let nut = CGRect(x: g.nutX - 3, y: g.neck.minY - 1, width: 6, height: g.neck.height + 2)
        context.fill(Path(roundedRect: nut, cornerRadius: 1.5), with: .color(FretboardPalette.bone))
    }

    /// Thicker, wound strings toward string 6; thin plain strings toward string 1.
    private func drawStrings(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        let count = diagram.stringCount
        let startX = FretboardGeometry.nameColumnWidth + 4
        for string in 0..<count {
            let width = 2.5 - 1.6 * CGFloat(string) / CGFloat(max(count - 1, 1)) // ≈2.5 pt down to ≈0.9 pt
            let isWound = string < count / 2
            let y = g.y(ofString: string)
            context.stroke(line(from: CGPoint(x: startX, y: y + 1), to: CGPoint(x: g.neck.maxX, y: y + 1)),
                           with: .color(.black.opacity(0.35)), lineWidth: width)
            context.stroke(line(from: CGPoint(x: startX, y: y), to: CGPoint(x: g.neck.maxX, y: y)),
                           with: .color(isWound ? FretboardPalette.woundString : FretboardPalette.plainString),
                           lineWidth: width)
        }
    }

    /// Dims the nut and the frets below the capo, then draws the bar just behind the capo fret.
    private func drawCapo(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        let capo = diagram.capo
        guard capo > 0, capo <= diagram.lastFret else { return }
        let x = g.wireX(capo - 1)
        let dimmed = CGRect(x: g.nutX - 3, y: g.neck.minY - 1, width: x - g.nutX + 3, height: g.neck.height + 2)
        context.fill(Path(dimmed), with: .color(.black.opacity(0.55)))
        let bar = CGRect(x: x - 6, y: g.neck.minY - 6, width: 10, height: g.neck.height + 12)
        context.fill(Path(roundedRect: bar, cornerRadius: 4),
                     with: .linearGradient(Gradient(colors: [FretboardPalette.capoLight, FretboardPalette.capoDark]),
                                           startPoint: CGPoint(x: bar.minX, y: 0), endPoint: CGPoint(x: bar.maxX, y: 0)))
    }

    private func drawStringNames(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        for (string, name) in diagram.stringNames.enumerated() {
            context.draw(Text(name).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary),
                         at: CGPoint(x: g.stringNameX, y: g.y(ofString: string)))
        }
    }

    private func drawFretRuler(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        guard diagram.lastFret >= 1 else { return }
        for fret in 1...diagram.lastFret {
            let marked = FretboardGeometry.inlayFrets.contains(fret)
            let text = Text("\(fret)")
                .font(.system(size: 9, weight: marked ? .semibold : .regular).monospacedDigit())
                .foregroundColor(marked ? .secondary : Color.secondary.opacity(0.45))
            context.draw(text, at: CGPoint(x: g.centerX(ofFret: fret), y: g.rulerY))
        }
    }

    /// Dots (root orange, tones blue) with a soft shadow, then the white ring and label on top.
    private func drawMarkers(in context: inout GraphicsContext, _ g: FretboardGeometry) {
        let markers = diagram.markers.filter {
            (0..<diagram.stringCount).contains($0.location.string) && (0...diagram.lastFret).contains($0.location.fret)
        }
        func dotRect(_ marker: FretboardDiagram.Marker) -> CGRect {
            let d = g.dotDiameter(atFret: marker.location.fret)
            let center = CGPoint(x: g.centerX(ofFret: marker.location.fret), y: g.y(ofString: marker.location.string))
            return CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
        }

        var shadowed = context
        shadowed.addFilter(.shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1))
        for marker in markers {
            shadowed.fill(Path(ellipseIn: dotRect(marker)), with: .color(FretboardPalette.color(for: marker.role)))
        }
        for marker in markers {
            let rect = dotRect(marker)
            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.85)), lineWidth: 1.25)
            drawLabel(marker.label, in: rect, context: &context)
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
        guard let fontSize = FretboardLabelLayout.fontSize(forDot: dot.width, measure: measure)
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
