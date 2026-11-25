/// One click: when it is heard, and its beat of the bar, from 1.
public struct ScheduledClick: Hashable, Sendable {
    public let time: Duration
    public let beat: Int
    public let isEmphasised: Bool
}

/// Clicks at a steady tempo from beat 1 of a bar, without end.
public struct ClickTrack: Hashable, Sendable {
    public let meter: Meter
    /// Counting clicks.
    public let bpm: Int
    /// When click 0 is heard.
    public let start: Duration

    public init(meter: Meter, bpm: Int, start: Duration) {
        precondition(bpm > 0)
        self.meter = meter
        self.bpm = bpm
        self.start = start
    }

    /// Worked out from the start, so that it doesn't drift. Clicks count from 0.
    public func time(ofClick index: Int) -> Duration { start + .seconds(60) * index / bpm }

    public func click(_ index: Int) -> ScheduledClick {
        let beat = index % meter.signature.beats + 1
        return ScheduledClick(time: time(ofClick: index), beat: beat, isEmphasised: meter.emphasis.contains(beat))
    }

    /// The first click at or after a time.
    func firstClick(from time: Duration) -> Int {
        guard time > start else { return 0 }
        // An estimate, then made exact.
        var index = max(0, Int((time - start) / .seconds(60) * Double(bpm)) - 1)
        while self.time(ofClick: index) < time { index += 1 }
        return index
    }
}

/// The clicks to be heard: one track after another.
public struct ClickSchedule: Hashable, Sendable {
    private struct Part: Hashable {
        let track: ClickTrack
        var end: Duration?
    }

    /// In order of time; only the last may have no end.
    private var parts: [Part] = []

    public init() {}

    /// From the track's start on, its clicks take the place of any others.
    public mutating func start(_ track: ClickTrack) {
        stop(at: track.start)
        parts.append(Part(track: track))
    }

    /// No clicks at or after a time.
    public mutating func stop(at time: Duration) {
        parts.removeAll { $0.track.start >= time }
        guard let last = parts.indices.last else { return }
        parts[last].end = min(parts[last].end ?? time, time)
    }

    /// Forgets tracks that have ended.
    public mutating func forget(before time: Duration) {
        parts.removeAll { $0.end.map { $0 <= time } ?? false }
    }

    /// Whether nothing is heard from a time on.
    public func isOver(at time: Duration) -> Bool {
        parts.allSatisfy { $0.end.map { $0 <= time } ?? false }
    }

    /// The clicks in a stretch of time, first to last.
    public func clicks(from start: Duration, before end: Duration) -> [ScheduledClick] {
        parts.flatMap { part in
            let end = min(end, part.end ?? end)
            var clicks: [ScheduledClick] = []
            var index = part.track.firstClick(from: start)
            while part.track.time(ofClick: index) < end {
                clicks.append(part.track.click(index))
                index += 1
            }
            return clicks
        }
    }

    /// The last click heard by a time; nil before the first, and once they have stopped.
    public func current(at time: Duration) -> ScheduledClick? {
        guard let part = parts.last(where: { $0.track.start <= time }), part.end.map({ time < $0 }) ?? true else { return nil }
        let next = part.track.firstClick(from: time)
        return part.track.click(part.track.time(ofClick: next) == time ? next : next - 1)
    }
}
