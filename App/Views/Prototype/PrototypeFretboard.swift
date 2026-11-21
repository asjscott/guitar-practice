// PROTOTYPE — throwaway. Shared fretboard drawing for the explorer variants.
// Real-neck spacing, high E on top, nut on the left, inlays, capo, label modes, heatmap tint.

import SwiftUI

struct PrototypeFretboard: View {
    let model: PrototypeExplorerModel

    var body: some View {
        Canvas { ctx, size in
            draw(&ctx, size)
        }
        .frame(minHeight: 200)
    }

    // Layout constants
    private let nameW: CGFloat = 22      // string-name column
    private let openW: CGFloat = 30      // open-string area left of the nut
    private let rightPad: CGFloat = 10
    private let numbersH: CGFloat = 20   // fret-number ruler under the neck

    // Palette
    private let woodTop = Color(red: 0.24, green: 0.16, blue: 0.11)
    private let woodBottom = Color(red: 0.17, green: 0.11, blue: 0.08)
    private let binding = Color(red: 0.93, green: 0.89, blue: 0.80)
    private let bone = Color(red: 0.95, green: 0.92, blue: 0.84)
    private let pearl = Color(red: 0.92, green: 0.91, blue: 0.87)
    private let fretWire = Color(red: 0.80, green: 0.80, blue: 0.78)
    private let wound = Color(red: 0.82, green: 0.72, blue: 0.55)
    private let plain = Color(red: 0.88, green: 0.88, blue: 0.88)
    private let rootColor = Color(red: 0.91, green: 0.45, blue: 0.23)
    private let toneColor = Color(red: 0.23, green: 0.51, blue: 0.96)

    private func wireX(_ n: Int, neckX: CGFloat, neckW: CGFloat) -> CGFloat {
        // Distance from the nut ∝ 1 − 2^(−n/12), scaled so wire 22 lands at the end of the neck.
        let full = 1 - pow(2, -Double(model.frets) / 12)
        return neckX + neckW * CGFloat((1 - pow(2, -Double(n) / 12)) / full)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let strings = model.tuning.open.count
        let neckX = nameW + openW
        let neckW = size.width - neckX - rightPad
        let neckTop: CGFloat = 4
        let neckH = size.height - numbersH - neckTop - 4
        let rowH = neckH / CGFloat(strings)
        func y(_ s: Int) -> CGFloat { neckTop + rowH * (CGFloat(strings - 1 - s) + 0.5) } // high E on top
        func wx(_ n: Int) -> CGFloat { wireX(n, neckX: neckX, neckW: neckW) }
        func cellX(_ f: Int) -> CGFloat { f == 0 ? nameW + openW / 2 : (wx(f - 1) + wx(f)) / 2 }
        func cellW(_ f: Int) -> CGFloat { f == 0 ? openW : wx(f) - wx(f - 1) }
        let neck = CGRect(x: neckX, y: neckTop, width: neckW, height: neckH)

        // Fingerboard
        ctx.fill(Path(roundedRect: neck, cornerRadius: 3),
                 with: .linearGradient(Gradient(colors: [woodTop, woodBottom]),
                                       startPoint: CGPoint(x: 0, y: neck.minY), endPoint: CGPoint(x: 0, y: neck.maxY)))
        for edge in [neck.minY + 0.75, neck.maxY - 0.75] {
            var p = Path(); p.move(to: .init(x: neck.minX, y: edge)); p.addLine(to: .init(x: neck.maxX, y: edge))
            ctx.stroke(p, with: .color(binding.opacity(0.9)), lineWidth: 1.5)
        }

        // Heatmap tint (under everything that sits on the board)
        if model.heatmap {
            for (c, v) in model.heat where c.string < strings && model.playable(c) {
                let x0 = c.fret == 0 ? nameW : wx(c.fret - 1)
                let r = CGRect(x: x0 + 1, y: y(c.string) - rowH / 2 + 1, width: cellW(c.fret) - 2, height: rowH - 2)
                let tint = Color(hue: 0.02 + 0.10 * (1 - v), saturation: 0.75, brightness: 1)
                ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(tint.opacity(0.04 + 0.30 * v * v)))
            }
        }

        // Inlays
        let midY = neck.midY
        func inlay(_ f: Int, _ cy: CGFloat) {
            let d = max(5, min(8, cellW(f) * 0.26))
            ctx.fill(Path(ellipseIn: CGRect(x: cellX(f) - d / 2, y: cy - d / 2, width: d, height: d)), with: .color(pearl.opacity(0.85)))
        }
        for f in [3, 5, 7, 9, 15, 17, 19, 21] { inlay(f, midY) }
        inlay(12, neckTop + rowH * 1.5); inlay(12, neck.maxY - rowH * 1.5)

        // Fret wires
        for n in 1...model.frets {
            let x = wx(n)
            var p = Path(); p.move(to: .init(x: x, y: neck.minY)); p.addLine(to: .init(x: x, y: neck.maxY))
            ctx.stroke(p, with: .color(.black.opacity(0.35)), style: .init(lineWidth: 1)) // shadow
            var h = Path(); h.move(to: .init(x: x - 1, y: neck.minY)); h.addLine(to: .init(x: x - 1, y: neck.maxY))
            ctx.stroke(h, with: .color(fretWire), lineWidth: 1.6)
        }
        // Nut
        ctx.fill(Path(roundedRect: CGRect(x: neckX - 3, y: neck.minY - 1, width: 6, height: neck.height + 2), cornerRadius: 1.5), with: .color(bone))

        // Strings: thicker and wound toward string 6
        for s in 0..<strings {
            let width = 2.5 - 1.6 * CGFloat(s) / CGFloat(max(strings - 1, 1)) // string 6 ≈ 2.5pt, string 1 ≈ 0.9pt
            let isWound = s < 3
            var shadow = Path(); shadow.move(to: .init(x: nameW + 4, y: y(s) + 1)); shadow.addLine(to: .init(x: neck.maxX, y: y(s) + 1))
            ctx.stroke(shadow, with: .color(.black.opacity(0.35)), lineWidth: width)
            var p = Path(); p.move(to: .init(x: nameW + 4, y: y(s))); p.addLine(to: .init(x: neck.maxX, y: y(s)))
            ctx.stroke(p, with: .color(isWound ? wound : plain), lineWidth: width)
        }

        // Capo: dim the unplayable frets, bar sits just behind the capo fret
        if model.capo > 0 {
            let x = wx(model.capo - 1)
            ctx.fill(Path(CGRect(x: nameW, y: neck.minY - 2, width: x - nameW, height: neck.height + 4)), with: .color(.black.opacity(0.55)))
            let bar = CGRect(x: x - 6, y: neck.minY - 6, width: 10, height: neck.height + 12)
            ctx.fill(Path(roundedRect: bar, cornerRadius: 4),
                     with: .linearGradient(Gradient(colors: [Color(white: 0.35), Color(white: 0.18)]),
                                           startPoint: CGPoint(x: bar.minX, y: 0), endPoint: CGPoint(x: bar.maxX, y: 0)))
        }

        // String names (from the tuning) and fret numbers
        for s in 0..<strings {
            ctx.draw(Text(model.name(model.tuning.open[s] % 12)).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary),
                     at: .init(x: nameW / 2, y: y(s)))
        }
        let marked: Set<Int> = [3, 5, 7, 9, 12, 15, 17, 19, 21]
        for f in 1...model.frets {
            let t = Text("\(f)").font(.system(size: 9, weight: marked.contains(f) ? .semibold : .regular).monospacedDigit())
                .foregroundColor(marked.contains(f) ? .secondary : Color.secondary.opacity(0.45))
            ctx.draw(t, at: .init(x: cellX(f), y: neck.maxY + numbersH / 2 + 2))
        }

        // Notes
        var dots = ctx
        dots.addFilter(.shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1))
        for c in model.highlighted where c.string < strings {
            let w = cellW(c.fret)
            let d = min(rowH * 0.78, max(w * 0.66, 11))
            let center = CGPoint(x: cellX(c.fret), y: y(c.string))
            let r = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
            dots.fill(Path(ellipseIn: r), with: .color(model.isRoot(c) ? rootColor : toneColor))
        }
        for c in model.highlighted where c.string < strings {
            let w = cellW(c.fret)
            let d = min(rowH * 0.78, max(w * 0.66, 11))
            let center = CGPoint(x: cellX(c.fret), y: y(c.string))
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)),
                       with: .color(.white.opacity(0.85)), lineWidth: 1.25)
            let fontSize = max(8, min(12, d * 0.48))
            if model.labelMode != .hidden, d >= 14 {
                let opacity = model.labelMode == .faded ? 0.3 : 1
                ctx.draw(Text(model.name(model.pitch(c) % 12)).font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(opacity)), at: center)
            }
        }
    }
}
