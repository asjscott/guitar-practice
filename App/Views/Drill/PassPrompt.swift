import PracticeCore
import SwiftUI
import TheoryCore

/// A scale drill (P4): what to play, the feedback, and the beats with the tempo; the neck zoomed to the position, with
/// the count-in over it; and the pass as a line. With no display (idle or paused), the resting text is in place of the
/// line, and the neck shows `restingMarkers`.
struct PassPrompt<Resting: View>: View {
    let display: DrillDisplay?
    /// What to zoom to at rest. Nil when it isn't on the neck, which is then shown whole.
    let position: Position?
    let restingMarkers: [FretboardDiagram.Marker]
    /// What the next pass is played at.
    let settings: PassSettings
    let fretboard: Fretboard
    @ViewBuilder let resting: Resting

    var body: some View {
        VStack(spacing: 12) {
            DrillHeader(display: display) { PassBeats(settings: display?.pass?.settings ?? settings) }
            FretboardView(diagram: diagram, minHeight: 120)
                .frame(maxHeight: .infinity)
                .overlay { if let beat = display?.pass?.countIn { CountInNumber(beat: beat) } }
                .padding(16)
                .sessionCard()
                .padding(.horizontal, 24)
            // The same height at rest, so that the neck stays still.
            Group {
                if let pass = display?.pass {
                    PassLine(notes: pass.notes)
                } else {
                    VStack(spacing: 4) { resting }.multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)
            .frame(height: 112)
        }
        .padding(.vertical, 12)
    }

    private var diagram: FretboardDiagram {
        var diagram = FretboardDiagram(drill: display, on: fretboard, fretWindow: display?.pass?.fretWindow ?? position?.fretWindow)
        if display == nil { diagram.markers = restingMarkers }
        return diagram
    }
}

/// The bar's beats as they click, then the tempo.
private struct PassBeats: View {
    let settings: PassSettings

    var body: some View {
        HStack(spacing: 14) {
            LiveBeatsRow(meter: settings.meter, size: settings.meter.signature.beats > 6 ? 15 : 24)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(settings.tempo)").font(.title.monospacedDigit().bold())
                Text("BPM").font(.callout).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        .fixedSize()
    }
}

private struct CountInNumber: View {
    let beat: Int

    var body: some View {
        Text("\(beat)")
            .font(.system(size: 150, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.7), radius: 8)
            .accessibilityLabel("Count-in, \(beat)")
            .allowsHitTesting(false)
    }
}

/// A pass as a line that rises and falls with pitch, with a dot per note.
private struct PassLine: View {
    let notes: [PassProgress.Note]

    var body: some View {
        Canvas { context, size in
            let dot: CGFloat = min(14, size.width / CGFloat(max(notes.count, 1)) * 0.7)
            func center(_ index: Int) -> CGPoint {
                CGPoint(x: size.width * (CGFloat(index) + 0.5) / CGFloat(notes.count),
                        y: dot + (size.height - 2 * dot) * (1 - notes[index].height))
            }
            var line = Path()
            line.addLines(notes.indices.map(center))
            context.stroke(line, with: .color(.secondary.opacity(0.35)), lineWidth: 2)
            for (index, note) in notes.enumerated() {
                let center = center(index)
                let circle = Path(ellipseIn: CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot))
                context.fill(circle, with: .color(Color(nsColor: .windowBackgroundColor)))
                context.fill(circle, with: .color(note.state.dotFill))
                context.stroke(circle, with: .color(note.state == .current ? .accentColor : .secondary.opacity(0.5)), lineWidth: 2)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Pass")
        .accessibilityValue("\(doneCount) of \(notes.count) notes")
    }

    private var doneCount: Int { notes.filter { $0.state == .found || $0.state == .timedOut }.count }
}

/// Key, Scale, Position and Fade.
struct ScaleOptions: View {
    let setup: DrillSetup
    @Binding var options: DrillOptions

    var body: some View {
        Picker("Key", selection: key) {
            ForEach(Key.appKeys(options.scaleKind.mode), id: \.self) { Text($0.tonic.description).tag($0) }
        }
        .help("Key (tonic)")
        Picker("Scale", selection: $options.scaleKind) {
            ForEach(Scale.Kind.allCases, id: \.self) { Text($0.name.capitalizedFirst).tag($0) }
        }
        .help("Scale")
        Picker("Position", selection: position) {
            if setup.position == nil { Text("None").tag(Position.ID?.none) }
            ForEach(setup.positions) { position in
                Text(position.octave == 0 ? position.name : "\(position.name) (octave up)").tag(Optional(position.id))
            }
        }
        .help("Position")
        FadePicker(stage: $options.pass.fadeStage, unit: "passes")
    }

    /// In the scale's mode.
    private var key: Binding<Key> {
        Binding(get: { options.key.withMode(options.scaleKind.mode) }, set: { options.key = $0 })
    }

    private var position: Binding<Position.ID?> {
        Binding(get: { setup.position?.id }, set: { if let id = $0 { options.position = id } })
    }
}

/// Follow, or a stage that overrides it.
struct FadePicker: View {
    @Binding var stage: FadeStage?
    /// What moves it, "passes".
    let unit: String

    var body: some View {
        Picker("Fade", selection: $stage) {
            Text("Follow").tag(FadeStage?.none)
            ForEach(FadeStage.allCases, id: \.self) { Text($0.rawValue.capitalizedFirst).tag(Optional($0)) }
        }
        .help("Fade stage (Follow: the one your clean \(unit) have reached)")
    }
}
