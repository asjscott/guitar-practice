import SwiftUI

/// The Tuner screen, T1 "Needle": a big note with its octave, an arc needle (±50 cents, green zone ±5), the
/// cents and Hz, the tuning's string chips with the nearest one lit, and the input line at the bottom.
/// A listening screen: audio input runs while it is open. Follows the tuning in Settings; ignores the capo.
struct TunerView: View {
    @State private var model = TunerViewModel()
    @Environment(AudioInputService.self) private var audioInput

    var body: some View {
        Group {
            if audioInput.permission == .denied {
                MicrophoneAccessDeniedView()
            } else {
                tuner
            }
        }
        .navigationTitle("Tuner")
        .navigationSubtitle(model.windowSubtitle)
        .listensToAudioInput(model.audioConsumer)
        .onDisappear { model.stopSounding() }
        .followsInstrumentSettings { tuning, _ in model.tuning = tuning }
    }

    private var tuner: some View {
        VStack(spacing: 18) {
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.noteName).font(.system(size: 120, weight: .semibold, design: .rounded))
                Text(model.octave).font(.system(size: 40, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(noteStyle)
            .accessibilityElement(children: .combine)

            TunerGauge(cents: model.cents, accuracy: model.accuracy)
                .frame(width: 460, height: 150)

            Text(model.detail)
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(model.stringChips) { chip in
                    TunerStringChip(chip: chip)
                }
            }
            Spacer()
            HStack {
                AudioInputLine()
                Spacer()
                AudioInputFallbackNotice().font(.caption)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    private var noteStyle: AnyShapeStyle {
        switch model.accuracy {
        case nil: AnyShapeStyle(Color.secondary.opacity(0.4))
        case .inTune: AnyShapeStyle(Color.green)
        case .close, .off: AnyShapeStyle(Color.primary)
        }
    }
}

extension TunerViewModel.Accuracy {
    /// Green in tune, yellow close, orange off.
    var color: Color {
        switch self {
        case .inTune: .green
        case .close: .yellow
        case .off: .orange
        }
    }
}

/// One string chip: the string number over its open pitch; lit and tinted on the nearest string.
private struct TunerStringChip: View {
    let chip: TunerViewModel.StringChip

    var body: some View {
        VStack(spacing: 2) {
            Text("\(chip.number)").font(.caption2).foregroundStyle(.secondary)
            Text(chip.openPitchName).font(.callout.weight(.semibold))
        }
        .frame(width: 54, height: 44)
        .background(RoundedRectangle(cornerRadius: 8).fill(chip.accuracy?.color.opacity(0.25) ?? Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(chip.accuracy?.color ?? .clear, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chip.accuracy != nil ? .isSelected : [])
    }
}

/// The arc needle: −50 to +50 cents across ±60°, a green zone at ±5 cents, ticks every 10 cents.
/// The needle shows only while sounding (`accuracy` non-nil), coloured by accuracy.
private struct TunerGauge: View {
    let cents: Double
    let accuracy: TunerViewModel.Accuracy?

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height - 8)
            let radius = min(size.width / 2, size.height) - 12
            func point(_ cents: Double, _ radius: CGFloat) -> CGPoint {
                let angle = Angle.degrees(-90 + cents / 50 * 60).radians
                return CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
            }
            var zone = Path()
            zone.addArc(center: center, radius: radius, startAngle: .degrees(-90 - 6), endAngle: .degrees(-90 + 6),
                        clockwise: false)
            context.stroke(zone, with: .color(.green.opacity(0.35)), lineWidth: 14)
            for tickCents in stride(from: -50, through: 50, by: 10) {
                var tick = Path()
                tick.move(to: point(Double(tickCents), radius - (tickCents == 0 ? 18 : 10)))
                tick.addLine(to: point(Double(tickCents), radius + 6))
                context.stroke(tick, with: .color(.secondary), lineWidth: tickCents == 0 ? 2.5 : 1)
            }
            if let accuracy {
                var needle = Path()
                needle.move(to: center)
                needle.addLine(to: point(max(-50, min(50, cents)), radius + 4))
                context.stroke(needle, with: .color(accuracy.color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)),
                         with: .color(.secondary))
        }
        .animation(.easeOut(duration: 0.12), value: cents)
        .accessibilityElement()
        .accessibilityLabel("Tuning needle")
        .accessibilityValue(accuracy == nil ? Text("No signal") : Text("\(Int(cents.rounded())) cents"))
    }
}

#Preview {
    TunerView()
        .environment(AudioInputService())
        .frame(width: 900, height: 600)
}
