import PracticeCore
import SwiftUI
import TheoryCore

// The neck and target card for a drill's display, shared by the Drill and session screens. They take plain values
// and know nothing of which drill is running.

extension FretboardDiagram {
    /// The neck for a drill: no labels except on the display's markers, its string highlighted. No display (idle,
    /// paused) draws the bare neck.
    init(drill display: DrillDisplay?, on fretboard: Fretboard) {
        self.init(stringNames: fretboard.stringNames(in: nil).map(\.description))
        capo = fretboard.capo
        labelMode = .shown
        markers = (display?.markers ?? []).map {
            Marker(location: $0.location, label: $0.label, role: $0.isAnswer ? .root : .tone)
        }
        highlightedString = display?.highlightedString
    }
}

/// The neck in its rounded card.
struct DrillNeck: View {
    let display: DrillDisplay?
    let fretboard: Fretboard
    var height: CGFloat = 210

    var body: some View {
        FretboardView(diagram: FretboardDiagram(drill: display, on: fretboard))
            .frame(height: height)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

/// How much of a prompt's time is left.
struct DrillCountdown: Equatable {
    /// Seconds.
    var remaining: Double
    /// The fraction of the time limit used, 0–1.
    var fraction: Double

    /// Nil unless the drill's prompt is waiting for an answer.
    init?(drill: any Drill, at now: Duration) {
        guard let remaining = drill.timeRemaining(at: now) else { return nil }
        self.remaining = remaining / .seconds(1)
        fraction = 1 - remaining / drill.timeLimit
    }
}

/// The target card with its countdown ring, and the feedback line under them.
struct DrillTarget: View {
    let display: DrillDisplay
    let countdown: DrillCountdown?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 24) {
                DrillTargetCard(tint: display.result.tint) {
                    Text(display.headline).font(.system(size: 76, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(display.subline).font(.title2).foregroundStyle(.secondary)
                }
                DrillCountdownRing(countdown: countdown).frame(width: 64, height: 64)
            }
            Label(display.feedback, systemImage: display.result.symbol)
                .foregroundStyle(display.result.color)
                .font(.title2.weight(.medium))
            if !display.chips.isEmpty { DrillChips(chips: display.chips) }
        }
    }
}

/// A chip per part of the prompt: string number over fret in a sweep.
private struct DrillChips: View {
    let chips: [DrillDisplay.Chip]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                VStack(spacing: 0) {
                    Text(chip.title).font(.caption.weight(.semibold))
                    Text(chip.text).font(.caption2)
                }
                .frame(width: 52, height: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill(chip.state.fill))
                .accessibilityElement()
                .accessibilityLabel("String \(chip.title): \(chip.state.spoken(chip.text))")
            }
        }
    }
}

/// The card alone, tinted by result.
struct DrillTargetCard<Content: View>: View {
    var tint = Color(nsColor: .controlBackgroundColor)
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 4) { content }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .frame(width: 320, height: 150)
            .background(RoundedRectangle(cornerRadius: 18).fill(tint))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(nsColor: .separatorColor)))
            .accessibilityElement(children: .combine)
    }
}

/// The time limit: a ring that empties as time runs out (orange in the last 30%), with the seconds left.
struct DrillCountdownRing: View {
    let countdown: DrillCountdown?

    var body: some View {
        let fraction = countdown?.fraction ?? 0
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0, to: 1 - fraction)
                .stroke(fraction > 0.7 ? Color.orange : Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(countdown.map { String(format: "%.1f", $0.remaining) } ?? "")
                .font(.callout.monospacedDigit())
        }
        .accessibilityElement()
        .accessibilityLabel("Time left")
        .accessibilityValue(countdown.map { Text("\(Int($0.remaining.rounded(.up))) seconds") } ?? Text("Not running"))
    }
}

private extension DrillDisplay.Chip.State {
    var fill: Color {
        switch self {
        case .waiting: .secondary.opacity(0.08)
        case .current: .accentColor.opacity(0.25)
        case .found: .green.opacity(0.2)
        case .timedOut: .orange.opacity(0.2)
        case .skipped: .gray.opacity(0.2)
        }
    }

    func spoken(_ text: String) -> String {
        switch self {
        case .waiting: "not found yet"
        case .current: "next"
        case .found: "found, \(text)"
        case .timedOut: "revealed, \(text)"
        case .skipped: "skipped"
        }
    }
}

private extension DrillDisplay.Result {
    var tint: Color {
        switch self {
        case .waiting: Color(nsColor: .controlBackgroundColor)
        case .wrong: .red.opacity(0.12)
        case .right: .green.opacity(0.15)
        case .timedOut: .orange.opacity(0.15)
        }
    }

    var color: Color {
        switch self {
        case .waiting: .secondary
        case .wrong: .red
        case .right: .green
        case .timedOut: .orange
        }
    }

    var symbol: String {
        switch self {
        case .waiting: "waveform"
        case .wrong: "xmark.circle.fill"
        case .right: "checkmark.circle.fill"
        case .timedOut: "clock.badge.exclamationmark"
        }
    }
}
