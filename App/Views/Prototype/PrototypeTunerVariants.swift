// PROTOTYPE — throwaway. Three tuner layouts for the Phase 1 screen prototype.

import SwiftUI
import TheoryCore

#if DEBUG

// MARK: - T1: Needle — classic chromatic tuner, big note, arc needle, string chips below

struct TunerT1: View {
    let listen: ProtoListen

    var body: some View {
        let cents = listen.tunerCents
        let on = listen.signal
        VStack(spacing: 18) {
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(listen.tunerNoteName).font(.system(size: 120, weight: .semibold, design: .rounded))
                Text("\(listen.tunerOctave)").font(.system(size: 40, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            }
            .foregroundStyle(on ? (listen.tunerInTune ? Color.green : Color.primary) : Color.secondary.opacity(0.4))

            ArcGauge(cents: cents, active: on)
                .frame(width: 460, height: 150)

            Text(on ? String(format: "%+.0f cents · %.1f Hz", cents, listen.tunerHz) : "Play a string")
                .font(.title3.monospacedDigit()).foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(listen.tuning.strings, id: \.self) { s in
                    let isNearest = s == listen.tunerString && on
                    VStack(spacing: 2) {
                        Text("\(listen.tuning.stringNumber(ofString: s))").font(.caption2).foregroundStyle(.secondary)
                        Text(listen.tuning.openPitchNames[s]).font(.callout.weight(.semibold))
                    }
                    .frame(width: 54, height: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(isNearest ? protoCentsColor(listen.tunerCentsFromString).opacity(0.25) : Color.secondary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isNearest ? protoCentsColor(listen.tunerCentsFromString) : .clear, lineWidth: 1.5))
                }
            }
            Spacer()
            HStack { ProtoInputLabel(level: on ? listen.level : 0.02); Spacer() }
                .padding(.horizontal, 24).padding(.bottom, 8)
        }
    }
}

private struct ArcGauge: View {
    let cents: Double
    let active: Bool

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height - 8)
            let r = min(size.width / 2, size.height) - 12
            func point(_ c: Double, _ radius: CGFloat) -> CGPoint {
                let a = Angle.degrees(-90 + c / 50 * 60).radians
                return CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y + radius * CGFloat(sin(a)))
            }
            // green zone
            var zone = Path()
            zone.addArc(center: center, radius: r, startAngle: .degrees(-90 - 6), endAngle: .degrees(-90 + 6), clockwise: false)
            ctx.stroke(zone, with: .color(.green.opacity(0.35)), lineWidth: 14)
            for c in stride(from: -50, through: 50, by: 10) {
                var tick = Path()
                tick.move(to: point(Double(c), r - (c == 0 ? 18 : 10)))
                tick.addLine(to: point(Double(c), r + 6))
                ctx.stroke(tick, with: .color(.secondary), lineWidth: c == 0 ? 2.5 : 1)
            }
            if active {
                var needle = Path()
                needle.move(to: center)
                needle.addLine(to: point(max(-50, min(50, cents)), r + 4))
                ctx.stroke(needle, with: .color(protoCentsColor(cents)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)), with: .color(.secondary))
        }
        .animation(.easeOut(duration: 0.12), value: cents)
    }
}

// MARK: - T2: Six strings — one column per string, the sounding one lights up with its own bar

struct TunerT2: View {
    let listen: ProtoListen

    var body: some View {
        let on = listen.signal
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(on ? "\(listen.tunerNoteName)\(listen.tunerOctave)" : "—").font(.system(size: 26, weight: .semibold))
                    Text(on ? String(format: "%.1f Hz · nearest %@", listen.tunerHz, listen.stringLabel(listen.tunerString)) : "Play a string").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                ProtoInputLabel(level: on ? listen.level : 0.02)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)

            HStack(spacing: 14) {
                // physical order left → right: string 6 … string 1
                ForEach(listen.tuning.strings, id: \.self) { s in
                    StringColumn(
                        number: listen.tuning.stringNumber(ofString: s),
                        name: listen.tuning.openPitchNames[s],
                        cents: s == listen.tunerString && on ? listen.tunerCentsFromString : nil)
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
            .padding(.horizontal, 24)

            Spacer(minLength: 16)
            Divider()
            HStack(spacing: 16) {
                Label("in tune ±5¢", systemImage: "circle.fill").foregroundStyle(.green)
                Label("close ±20¢", systemImage: "circle.fill").foregroundStyle(.yellow)
                Label("off", systemImage: "circle.fill").foregroundStyle(.orange)
                Spacer()
                Text("Standard · capo ignored when tuning").foregroundStyle(.secondary)
            }
            .font(.caption).padding(.horizontal, 24).frame(height: 32).background(.bar)
        }
    }
}

private struct StringColumn: View {
    let number: Int
    let name: String
    let cents: Double?

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let h = geo.size.height
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(cents == nil ? 0.06 : 0.12))
                    Rectangle().fill(Color.green.opacity(0.25)).frame(height: h * 0.1)
                    Rectangle().fill(Color.secondary.opacity(0.5)).frame(height: 1)
                    if let cents {
                        let c = max(-50, min(50, cents))
                        Capsule().fill(protoCentsColor(cents)).frame(width: geo.size.width - 10, height: 8)
                            .offset(y: -CGFloat(c / 50) * h / 2)
                        Text(String(format: "%+.0f", cents)).font(.title3.monospacedDigit().weight(.semibold))
                            .offset(y: c > 0 ? h * 0.38 : -h * 0.38)
                    }
                }
            }
            Text(name).font(.title2.weight(.semibold)).foregroundStyle(cents == nil ? .secondary : .primary)
            Text("string \(number)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.12), value: cents)
    }
}

// MARK: - T3: On the neck — the real fretboard with the sounding string lit, a wide cents tape below

struct TunerT3: View {
    let listen: ProtoListen

    var body: some View {
        let on = listen.signal
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(on ? listen.tunerNoteName : "—").font(.system(size: 72, weight: .semibold, design: .rounded))
                        .foregroundStyle(on && listen.tunerInTune ? .green : .primary)
                    Text(on ? String(format: "octave %d · %.1f Hz", listen.tunerOctave, listen.tunerHz) : "Play a string")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(width: 180, alignment: .leading)
                CentsTape(cents: on ? listen.tunerCents : nil)
                    .frame(height: 90)
            }
            .padding(.horizontal, 24).padding(.top, 20)

            FretboardView(diagram: FretboardDiagram(stringNames: listen.stringNames, lastFret: 5))
                .overlay { if on { ProtoStringBand(string: listen.tunerString, stringCount: 6, color: protoCentsColor(listen.tunerCentsFromString)) } }
                .frame(height: 220)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
                .padding(.horizontal, 24)

            Spacer(minLength: 8)
            Divider()
            HStack {
                Text(on ? "Nearest: \(listen.stringLabel(listen.tunerString)), \(String(format: "%+.0f", listen.tunerCentsFromString)) cents" : "Waiting for a note")
                    .foregroundStyle(.secondary)
                Spacer()
                ProtoInputLabel(level: on ? listen.level : 0.02)
            }
            .font(.caption).padding(.horizontal, 24).frame(height: 32).background(.bar)
        }
    }
}

private struct CentsTape: View {
    let cents: Double?

    var body: some View {
        Canvas { ctx, size in
            let midX = size.width / 2
            let perCent = size.width / 100
            ctx.fill(Path(CGRect(x: midX - 5 * perCent, y: 0, width: 10 * perCent, height: size.height)), with: .color(.green.opacity(0.18)))
            for c in -50...50 where c % 5 == 0 {
                let x = midX + CGFloat(c) * perCent
                let len: CGFloat = c % 10 == 0 ? 22 : 12
                var p = Path(); p.move(to: CGPoint(x: x, y: size.height - len)); p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(.secondary.opacity(c == 0 ? 1 : 0.6)), lineWidth: c == 0 ? 2 : 1)
                if c % 25 == 0 {
                    ctx.draw(Text(c == 0 ? "0" : String(format: "%+d", c)).font(.caption2).foregroundColor(.secondary), at: CGPoint(x: x, y: size.height - 32))
                }
            }
            if let cents {
                let x = midX + CGFloat(max(-50, min(50, cents))) * perCent
                let r = CGRect(x: x - 7, y: 6, width: 14, height: size.height - 44)
                ctx.fill(Path(roundedRect: r, cornerRadius: 7), with: .color(protoCentsColor(cents)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: cents)
    }
}
#endif
