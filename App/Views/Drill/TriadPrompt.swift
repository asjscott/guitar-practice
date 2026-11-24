import PracticeCore
import SwiftUI
import TheoryCore

/// A triad drill (P4): what to play and the feedback, with the countdown ring; the neck, showing the whole practised
/// range; and a circle per string, with its note once played. With no display (idle or paused), the resting text is
/// in place of the circles.
struct TriadPrompt<Countdown: View, Resting: View>: View {
    let display: DrillDisplay?
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
            Group {
                if let display {
                    TriadCircles(chips: display.chips)
                } else {
                    VStack(spacing: 4) { resting }.multilineTextAlignment(.center)
                }
            }
            .frame(height: 112)
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

    var body: some View {
        HStack(spacing: 40) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                VStack(spacing: 4) {
                    Circle()
                        .fill(chip.state.fill)
                        .overlay { if chip.state == .current { Circle().strokeBorder(Color.accentColor, lineWidth: 2) } }
                        .overlay { Text(chip.text).font(.title.bold()) }
                        .frame(width: 72, height: 72)
                    Text(chip.spokenTitle).font(.callout).foregroundStyle(.secondary)
                }
                .accessibilityElement()
                .accessibilityLabel("\(chip.spokenTitle): \(chip.state.spoken(chip.text))")
            }
        }
    }
}

/// Key, String sets, Inversions and Frets.
struct TriadOptions: View {
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
        Menu(title("Inversions", options.inversions, of: Triad.Inversion.allCases, name: \.shortName)) {
            ForEach(Triad.Inversion.allCases, id: \.self) { Toggle($0.name, isOn: included($0, in: \.inversions)) }
        }
        .help("Inversions")
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

private extension Triad.Inversion {
    var shortName: String {
        switch self {
        case .root: "root"
        case .first: "1st"
        case .second: "2nd"
        }
    }
}
