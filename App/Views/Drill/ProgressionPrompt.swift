import PracticeCore
import SwiftUI
import TheoryCore

/// A progression drill, screen B (see "Progressions (Phase 4)" in docs/ui.md): a header line with the progression's
/// chords, the feedback and the time through; the tall neck, zoomed to the position, with the count-in over it; then
/// the timeline of chords. With no display (idle or paused), the position on the neck and the resting text in place of
/// the timeline. Notices about how the backing will be heard go under it.
struct ProgressionPrompt<Resting: View>: View {
    let display: DrillDisplay?
    let position: Position?
    let fretboard: Fretboard
    var notices: [String] = []
    @ViewBuilder let resting: Resting

    var body: some View {
        VStack(spacing: 12) {
            DrillHeader(display: display) {
                if let progress = display?.progression {
                    Text(progress.timeThroughText).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            FretboardView(diagram: diagram, minHeight: 120)
                .frame(maxHeight: .infinity)
                .overlay { if let beat = display?.progression?.countIn { CountInNumber(beat: beat) } }
                .padding(16)
                .sessionCard()
                .padding(.horizontal, 24)
            // The same height at rest, so that the neck stays still.
            Group {
                if let progress = display?.progression {
                    ProgressionTimeline(progress: progress)
                        .sessionCard()
                } else {
                    VStack(spacing: 4) { resting }.multilineTextAlignment(.center).frame(maxHeight: .infinity)
                }
            }
            .frame(height: display?.progression?.topNotes == nil ? 110 : 150)
            .padding(.horizontal, 24)
            VStack(spacing: 2) {
                ForEach(notices, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            .font(.callout)
            .frame(minHeight: 36)
        }
        .padding(.vertical, 12)
    }

    private var diagram: FretboardDiagram {
        var diagram = FretboardDiagram(drill: display, on: fretboard,
                                       fretWindow: display?.progression?.fretWindow ?? position?.fretWindow)
        if display == nil, let position {
            diagram.markers = position.locations.map { .init($0, of: position.scale, on: fretboard) }
            for index in diagram.markers.indices { diagram.markers[index].isFaint = true }
        }
        return diagram
    }
}

/// The time through's chords as blocks, a mark per beat, scrolling left past a fixed playhead; the next time through
/// comes in from the right. Past blocks are tinted by outcome, the current one outlined. In Target top note, the line
/// of top notes rises and falls under the blocks, each note named. One view, so that a row of chord cards (screen A)
/// could take its place.
struct ProgressionTimeline: View {
    let progress: ProgressionProgress

    private static let beatWidth: CGFloat = 46
    private static let playheadShare: CGFloat = 0.25
    /// The height the top-note line takes, under the blocks.
    private static let lineBand: CGFloat = 48

    var body: some View {
        GeometryReader { geometry in
            let playhead = geometry.size.width * Self.playheadShare
            let band = progress.topNotes == nil ? 0 : Self.lineBand
            ZStack(alignment: .topLeading) {
                ForEach(timesThrough, id: \.self) { timeThrough in
                    ForEach(Array(progress.blocks.enumerated()), id: \.offset) { index, block in
                        placedBlock(block, index: index, timeThrough: timeThrough, playhead: playhead,
                                    height: geometry.size.height - 20 - band)
                    }
                }
                if let topNotes = progress.topNotes {
                    topLine(topNotes, playhead: playhead, top: geometry.size.height - band - 4, height: band)
                }
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 3, height: geometry.size.height)
                    .offset(x: playhead - 1.5)
            }
        }
        .clipped()
        .accessibilityElement()
        .accessibilityLabel("Chords")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let chords: String = progress.blocks.map(\.name).joined(separator: ", ")
        guard let topNotes = progress.topNotes else { return chords }
        let names: String = topNotes.map(\.name).joined(separator: ", ")
        return chords + "; top notes " + names
    }

    /// One chord block, sized by its beats and placed along the timeline. Split out so the compiler can type-check
    /// the timeline's body in reasonable time (CI's Xcode timed out on it).
    private func placedBlock(_ block: ProgressionProgress.Block, index: Int, timeThrough: Int, playhead: CGFloat,
                             height: CGFloat) -> some View {
        let isThis = timeThrough == 0
        let width: CGFloat = CGFloat(block.beats) * Self.beatWidth - 6
        let left: CGFloat = x(timeThrough: timeThrough, block: index, playhead: playhead) + 3
        return blockView(block, isCurrent: isThis && index == progress.current, hasOutcome: isThis)
            .frame(width: width, height: height)
            .opacity(isThis ? 1 : 0.5)
            .offset(x: left, y: 10)
    }

    /// Where a block starts, in a time through (0 = this one, -1 the one before, 1 the next).
    private func x(timeThrough: Int, block index: Int, playhead: CGFloat) -> CGFloat {
        let beatsPerTimeThrough = progress.blocks.map(\.beats).reduce(0, +)
        let start = Double(timeThrough * beatsPerTimeThrough + beatsBefore(index))
        return playhead + CGFloat(start - progress.beat) * Self.beatWidth
    }

    /// The top notes, one at the start of each block, joined, higher notes higher; each named.
    private func topLine(_ notes: [ProgressionProgress.TopNote], playhead: CGFloat, top: CGFloat,
                         height: CGFloat) -> some View {
        let pitches = notes.map(\.pitch.midi)
        let low = pitches.min() ?? 0, high = max(pitches.max() ?? 0, low + 1)
        let points = timesThrough.flatMap { timeThrough in
            notes.indices.map { index in
                let y = top + (height - 24) * CGFloat(high - notes[index].pitch.midi) / CGFloat(high - low) + 10
                return (point: CGPoint(x: x(timeThrough: timeThrough, block: index, playhead: playhead) + 22, y: y),
                        name: notes[index].name, timeThrough: timeThrough)
            }
        }
        return ZStack(alignment: .topLeading) {
            Path { $0.addLines(points.map(\.point)) }.stroke(Color.purple.opacity(0.5), lineWidth: 2)
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                Text(point.name)
                    .font(.callout.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.purple))
                    .opacity(point.timeThrough == 0 ? 1 : 0.5)
                    .position(point.point)
            }
        }
    }

    /// The time through before, while it can still be seen, this one and the next.
    private var timesThrough: [Int] { progress.beat < 0 ? [0, 1] : [-1, 0, 1] }

    private func beatsBefore(_ index: Int) -> Int { progress.blocks[..<index].map(\.beats).reduce(0, +) }

    private func blockView(_ block: ProgressionProgress.Block, isCurrent: Bool, hasOutcome: Bool) -> some View {
        let outcome = hasOutcome ? block.outcome : nil
        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(block.name).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(block.numeral).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(0..<block.beats, id: \.self) { beat in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 1.5, height: beat % 4 == 0 ? 12 : 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(fill(outcome, isCurrent: isCurrent)))
        .overlay { if isCurrent { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2) } }
    }

    private func fill(_ outcome: ChordOutcome?, isCurrent: Bool) -> Color {
        switch outcome {
        case .clean: .green.opacity(0.25)
        case .wrong: .orange.opacity(0.25)
        case .missed: .gray.opacity(0.25)
        case nil: isCurrent ? .accentColor.opacity(0.15) : .secondary.opacity(0.08)
        }
    }
}

/// Key, Progression (of the key's mode), Position, Style and Tempo.
struct ProgressionOptions: View {
    @Bindable var model: DrillViewModel

    var body: some View {
        Picker("Key", selection: $model.progressionKey) {
            ForEach(Key.Mode.allCases, id: \.self) { mode in
                Section(mode.rawValue.capitalized) {
                    ForEach(Key.appKeys(mode), id: \.self) { Text($0.description).tag($0) }
                }
            }
        }
        .help("Key")
        Picker("Progression", selection: $model.progression) {
            ForEach(Progression.library(model.options.key.mode)) { Text($0.name).tag($0) }
        }
        .help("Progression")
        Picker("Position", selection: position) {
            if model.progressionPosition == nil { Text("None").tag(Position.ID?.none) }
            ForEach(positions) { position in
                Text(position.octave == 0 ? position.name : "\(position.name) (octave up)").tag(Optional(position.id))
            }
        }
        .help("Position")
        Picker("Style", selection: $model.backingSettings.style) {
            ForEach(BackingStyle.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .help("Backing style")
        HStack(spacing: 4) {
            Text("♩ = \(model.backingSettings.tempo)").monospacedDigit()
            Stepper("Tempo", value: $model.backingSettings.tempo, in: 40...160, step: 2).labelsHidden()
        }
        .help("Tempo (BPM)")
    }

    private var positions: [Position] {
        model.fretboard.positions(of: model.options.key.scale, system: model.options.positionSystem)
    }

    private var position: Binding<Position.ID?> {
        Binding(get: { model.progressionPosition?.id }, set: { if let id = $0 { model.options.position = id } })
    }
}

extension BackingStyle {
    /// "Rock", "Pop ballad".
    var title: String {
        switch self {
        case .rock: "Rock"
        case .popBallad: "Pop ballad"
        case .bluesShuffle: "Blues shuffle"
        }
    }
}
