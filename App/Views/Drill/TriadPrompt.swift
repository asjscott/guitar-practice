import PracticeCore
import SwiftUI
import TheoryCore

/// A triad drill (P4): what to play and the feedback, with the countdown ring; the neck, showing the whole practised
/// range; a climb's line of voicings; and a circle per string, with its note once played. With no display (idle or paused), the resting text is
/// in place of the circles.
struct TriadPrompt<Countdown: View, Resting: View>: View {
    let display: DrillDisplay?
    let hasClimbs: Bool
    let frets: ClosedRange<Int>
    let fretboard: Fretboard
    @ViewBuilder let countdown: Countdown
    @ViewBuilder let resting: Resting

    var body: some View {
        VStack(spacing: 12) {
            header
                .frame(height: 56)
                .padding(.horizontal, 28)
            FretboardView(diagram: FretboardDiagram(drill: display, on: fretboard, fretWindow: frets))
                .frame(maxHeight: .infinity)
                .padding(16)
                .sessionCard()
                .padding(.horizontal, 24)
            // The same height at rest, so that the neck stays still.
            Group {
                if let display {
                    VStack(spacing: 8) {
                        if hasClimbs { ClimbLine(voicings: display.voicings) }
                        TriadCircles(chips: display.chips, size: hasClimbs ? 56 : 72)
                    }
                } else {
                    VStack(spacing: 4) { resting }.multilineTextAlignment(.center)
                }
            }
            .frame(height: hasClimbs ? 140 : 112)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 20) {
            if let display {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(display.headline).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(display.subline).font(.title2).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                Label(display.feedback, systemImage: display.symbol)
                    .foregroundStyle(display.result.color)
                    .font(.title2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                countdown.frame(width: 50, height: 50)
            }
        }
    }
}

/// A circle per string, lowest first.
private struct TriadCircles: View {
    let chips: [DrillDisplay.Chip]
    let size: CGFloat

    var body: some View {
        HStack(spacing: 40) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                VStack(spacing: 4) {
                    Circle()
                        .fill(chip.state.fill)
                        .overlay { if chip.state == .current { Circle().strokeBorder(Color.accentColor, lineWidth: 2) } }
                        .overlay { Text(chip.text).font(.title.bold()) }
                        .frame(width: size, height: size)
                    Text(chip.spokenTitle).font(.callout).foregroundStyle(.secondary)
                }
                .accessibilityElement()
                .accessibilityLabel("\(chip.spokenTitle): \(chip.state.spoken(chip.text))")
            }
        }
    }
}

/// A climb as a line that rises and falls, with a dot per voicing over its inversion.
private struct ClimbLine: View {
    let voicings: [DrillDisplay.Chip]

    private static let spacing: CGFloat = 46
    private static let rise: CGFloat = 18
    private static let dotSize: CGFloat = 16

    var body: some View {
        ZStack {
            Path { path in path.addLines(voicings.indices.map(center)) }
                .stroke(Color.secondary.opacity(0.35), lineWidth: 2)
            ForEach(Array(voicings.enumerated()), id: \.offset) { index, chip in
                let center = center(index)
                dot(chip).position(center)
                Text(chip.title)
                    .font(.caption.weight(chip.state == .current ? .bold : .regular))
                    .foregroundStyle(chip.state == .current ? .primary : .secondary)
                    .position(x: center.x, y: center.y + Self.dotSize + 1)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: Self.spacing * CGFloat(voicings.count), height: Self.rise + Self.dotSize + 18)
    }

    /// The highest voicing is in the middle of the line.
    private func center(_ index: Int) -> CGPoint {
        let top = voicings.count / 2
        let drop = top == 0 ? 0 : CGFloat(abs(index - top)) / CGFloat(top)
        return CGPoint(x: Self.spacing * (CGFloat(index) + 0.5), y: Self.dotSize / 2 + Self.rise * drop)
    }

    private func dot(_ chip: DrillDisplay.Chip) -> some View {
        Circle()
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay { Circle().fill(chip.state.dotFill) }
            .overlay { Circle().strokeBorder(chip.state == .current ? Color.accentColor : .secondary.opacity(0.5), lineWidth: 2) }
            .frame(width: Self.dotSize, height: Self.dotSize)
            .accessibilityElement()
            .accessibilityLabel("\(chip.spokenTitle): \(chip.state.spoken(chip.text))")
    }
}

private extension DrillDisplay.Chip.State {
    /// Stronger than `fill`, for a dot.
    var dotFill: Color {
        switch self {
        case .waiting: .clear
        case .current: .accentColor.opacity(0.25)
        case .found: .green
        case .timedOut: .orange
        case .skipped: .gray
        }
    }
}

/// Key, String sets, Inversions (where the drill offers them) and Frets.
struct TriadOptions: View {
    let kind: DrillKind
    @Binding var options: DrillOptions

    var body: some View {
        Picker("Key", selection: $options.key) {
            ForEach(Key.Mode.allCases, id: \.self) { mode in
                Section(mode.rawValue.capitalized) {
                    ForEach(Key.appKeys(mode), id: \.self) { Text($0.description).tag($0) }
                }
            }
        }
        .help("Key")
        Menu(title("Sets", options.stringSets, of: StringSet.allCases, name: \.name)) {
            ForEach(StringSet.allCases, id: \.self) { Toggle($0.name, isOn: included($0, in: \.stringSets)) }
        }
        .help("String sets")
        if kind.offersInversions {
            Menu(title("Inversions", options.inversions, of: Triad.Inversion.allCases, name: \.shortName)) {
                ForEach(Triad.Inversion.allCases, id: \.self) { Toggle($0.name, isOn: included($0, in: \.inversions)) }
            }
            .help("Inversions")
        }
        FretsPicker(frets: $options.frets)
    }

    /// "Sets: all", or the only one, or how many.
    private func title<Choice: Hashable>(_ label: String, _ included: Set<Choice>, of all: [Choice], name: (Choice) -> String) -> String {
        if included.count == all.count { return "\(label): all" }
        let names = all.filter(included.contains).map(name)
        return "\(label): " + (names.count == 1 ? names[0] : "\(names.count)")
    }

    /// Whether a choice is included; at least one always stays in.
    private func included<Choice: Hashable>(_ choice: Choice, in choices: WritableKeyPath<DrillOptions, Set<Choice>>) -> Binding<Bool> {
        Binding(
            get: { options[keyPath: choices].contains(choice) },
            set: { isOn in
                if isOn {
                    options[keyPath: choices].insert(choice)
                } else if options[keyPath: choices].count > 1 {
                    options[keyPath: choices].remove(choice)
                }
            })
    }
}
