// PROTOTYPE, throwaway. The three Phase 4 variants' layouts.
import SwiftUI
import TheoryCore

/// The header line over the neck, as Phase 3's P4: what's playing now, the feedback, the beats.
private struct P4Header: View {
    let m: P4Model
    var body: some View {
        HStack(spacing: 18) {
            if let c = m.current {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(c.name).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(c.numeral).font(.title2).foregroundStyle(.secondary)
                    if m.drill == .top { Text("top \(m.topName(c))").font(.title2).foregroundStyle(.purple) }
                }
            } else {
                Text("Count-in").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer()
            if let (text, color) = m.feedback { Text(text).font(.title2.weight(.medium)).foregroundStyle(color) }
            P4Beats(m: m)
        }
        .frame(height: 56).padding(.horizontal, 28)
    }
}

private struct P4CountInOverlay: View {
    let m: P4Model
    var body: some View {
        if m.scene == .countIn {
            Text("\(m.beatInBar + 1)").font(.system(size: 120, weight: .heavy, design: .rounded)).foregroundStyle(.orange.opacity(0.85))
        }
    }
}

// MARK: - A: the Phase 3 layout, with a row of chord cards under the neck

struct P4VariantA: View {
    let m: P4Model
    var body: some View {
        VStack(spacing: 12) {
            P4Header(m: m)
            FretboardView(diagram: m.diagram(for: m.current ?? m.chords.first), minHeight: 120)
                .frame(maxHeight: .infinity).padding(16).sessionCard().padding(.horizontal, 24)
                .overlay { P4CountInOverlay(m: m) }
            HStack(spacing: 8) {
                ForEach(m.chords) { card($0) }
            }
            .padding(.horizontal, 24)
            Text("\(ordinal(m.timeThrough)) time through · \(m.drill.rawValue) · \(m.stage.rawValue)")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    private func card(_ c: P4Chord) -> some View {
        let isNow = c.id == m.currentIndex, outcome = m.outcome(c)
        let progress = isNow ? Double(m.beat - c.start + 1) / Double(c.beats) : 0
        return VStack(spacing: 4) {
            if m.drill == .top {
                Text(m.stage == .hidden && c.id > m.currentIndex ? "?" : m.topName(c))
                    .font(.callout.bold()).foregroundStyle(.purple)
            }
            Text(c.name).font(.system(size: m.chords.count > 6 ? 20 : 30, weight: .bold, design: .rounded))
            Text(c.numeral).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(i < m.notesPlayed(c) ? (outcome?.color ?? .accentColor) : .secondary.opacity(0.2)).frame(width: 7, height: 7)
                }
            }
        }
        .frame(maxWidth: .infinity).frame(height: m.drill == .top ? 104 : 84)
        .background(alignment: .leading) {
            GeometryReader { g in Rectangle().fill(Color.accentColor.opacity(0.12)).frame(width: g.size.width * progress) }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill((outcome?.color ?? .clear).opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isNow ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isNow ? 2.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .layoutPriority(Double(c.bars))
        .frame(minWidth: CGFloat(c.bars) * 40)
    }
}

func ordinal(_ n: Int) -> String { "\(n)\(n == 1 ? "st" : n == 2 ? "nd" : n == 3 ? "rd" : "th")" }

// MARK: - B: a timeline that scrolls past a playhead, the next voicing ghosted on the neck

struct P4VariantB: View {
    let m: P4Model
    private let beatWidth: CGFloat = 46

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(m.drill.rawValue) · \(m.progressionText)").font(.title2.bold())
                Spacer()
                if let (text, color) = m.feedback { Text(text).font(.title3.weight(.medium)).foregroundStyle(color) }
                Text("\(ordinal(m.timeThrough)) time · \(m.stage.rawValue)").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28).frame(height: 44)
            FretboardView(diagram: m.diagram(for: m.current ?? m.chords.first, preview: next), minHeight: 120)
                .frame(maxHeight: .infinity).padding(16).sessionCard().padding(.horizontal, 24)
                .overlay { P4CountInOverlay(m: m) }
            timeline.frame(height: m.drill == .top ? 150 : 110).sessionCard().padding(.horizontal, 24)
        }
        .padding(.vertical, 12)
    }

    private var next: P4Chord? {
        guard let c = m.current else { return m.chords.first }
        return m.chords[(c.id + 1) % m.chords.count]
    }

    /// Two times through laid end to end, so the next one is coming in from the right.
    private var timeline: some View {
        GeometryReader { g in
            let playhead = g.size.width * 0.25
            let offset = playhead - CGFloat(max(0, m.scene == .countIn ? -4 + m.beat : m.beat)) * beatWidth - beatWidth / 2
            ZStack(alignment: .topLeading) {
                ForEach(0..<2, id: \.self) { lap in
                    ForEach(m.chords) { c in
                        let x = offset + CGFloat(lap * m.totalBeats + c.start) * beatWidth
                        block(c, lap: lap).frame(width: CGFloat(c.beats) * beatWidth - 4).offset(x: x, y: 8)
                    }
                }
                if m.drill == .top { topLine(offset: offset) }
                Rectangle().fill(Color.orange).frame(width: 3).offset(x: playhead).padding(.vertical, 2)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .clipped()
        }
    }

    private func block(_ c: P4Chord, lap: Int) -> some View {
        let outcome = lap == 0 ? m.outcome(c) : nil
        let isNow = lap == 0 && c.id == m.currentIndex
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(c.name).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(c.numeral).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                ForEach(0..<c.beats, id: \.self) { b in
                    Rectangle().fill(b % 4 == 0 ? Color.secondary.opacity(0.6) : .secondary.opacity(0.25)).frame(width: 1, height: b % 4 == 0 ? 14 : 8)
                        .frame(width: beatWidth, alignment: .leading)
                }
            }
        }
        .padding(.leading, 8).padding(.vertical, 6)
        .frame(height: 78, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill((outcome?.color ?? (isNow ? .accentColor : .secondary)).opacity(isNow || outcome != nil ? 0.2 : 0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isNow ? Color.accentColor : .clear, lineWidth: 2))
        .opacity(lap == 0 ? 1 : 0.6)
    }

    /// The top notes as a line that rises and falls over the blocks.
    private func topLine(offset: CGFloat) -> some View {
        let tops = (0..<2).flatMap { lap in m.chords.map { (lap, $0) } }
        let pitches = m.chords.compactMap { $0.voicing.map { m.pitches($0)[2] } }
        let lo = pitches.min() ?? 60, hi = max(pitches.max() ?? 60, lo + 1)
        func point(_ lap: Int, _ c: P4Chord) -> CGPoint {
            let p = c.voicing.map { m.pitches($0)[2] } ?? lo
            return CGPoint(x: offset + CGFloat(lap * m.totalBeats + c.start) * beatWidth + 18, y: 128 - CGFloat(p - lo) / CGFloat(hi - lo) * 34)
        }
        return ZStack(alignment: .topLeading) {
            Path { path in path.addLines(tops.map { point($0.0, $0.1) }) }.stroke(Color.purple.opacity(0.5), lineWidth: 2)
            ForEach(Array(tops.enumerated()), id: \.offset) { _, t in
                Text(m.topName(t.1)).font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(.purple)).position(point(t.0, t.1))
            }
        }
    }
}

// MARK: - C: a lead sheet, a small neck in every bar, no big neck

struct P4VariantC: View {
    let m: P4Model

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                Text(m.drill.rawValue).font(.title2.bold())
                Text("\(ordinal(m.timeThrough)) time through · \(m.stage.rawValue)").foregroundStyle(.secondary)
                Spacer()
                if let (text, color) = m.feedback { Text(text).font(.title3.weight(.medium)).foregroundStyle(color) }
                P4Beats(m: m, size: 16)
            }
            .padding(.horizontal, 28).frame(height: 44)
            let rows = stride(from: 0, to: bars.count, by: 4).map { Array(bars[$0..<min($0 + 4, bars.count)]) }
            VStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(row, id: \.bar) { item in cell(item) }
                        if row.count < 4 { Color.clear.frame(maxWidth: .infinity).layoutPriority(Double(4 - row.count)) }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .overlay { P4CountInOverlay(m: m) }
        }
        .padding(.vertical, 12)
    }

    private struct Bar { let bar: Int; let chord: P4Chord; let isFirst: Bool }

    private var bars: [Bar] {
        m.chords.flatMap { c in (0..<c.bars).map { Bar(bar: c.start / 4 + $0, chord: c, isFirst: $0 == 0) } }
    }

    private func cell(_ item: Bar) -> some View {
        let c = item.chord, outcome = m.outcome(c)
        let isNow = c.id == m.currentIndex && m.beat / 4 == item.bar
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.isFirst ? c.name : "%").font(.system(size: 22, weight: .bold, design: .rounded))
                Text(item.isFirst ? c.numeral : "").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if m.drill == .top, item.isFirst {
                    Text(m.topName(c)).font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 5)
                        .background(Capsule().fill(.purple))
                }
            }
            if item.isFirst {
                FretboardView(diagram: m.diagram(for: c, backdrop: m.stage == .hidden), minHeight: 40).frame(maxHeight: .infinity)
            } else {
                Spacer()
            }
            if isNow {
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { b in Capsule().fill(b <= m.beatInBar ? Color.orange : .secondary.opacity(0.25)).frame(height: 4) }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Rectangle().fill((outcome?.color ?? (isNow ? .accentColor : .clear)).opacity(0.12)))
        .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.6)).frame(width: 1.5) }
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isNow ? Color.accentColor : .clear, lineWidth: 2.5))
    }
}
