/// The latency check in Settings › Audio: a bar of count-in, then eight clicks at 80 BPM, with a muted note played on
/// each. The input delay is the median time from each click as heard to its onset (see "Input delay" in
/// GLOSSARY.md). Times are on the drill clock.
public struct LatencyCheck: Hashable, Sendable {
    public static let bpm = 80
    /// Played on, after the count-in.
    public static let clicks = 8
    /// Clicks with a note heard, at least, for a measurement.
    public static let needed = 6

    public enum Result: Hashable, Sendable {
        /// Never less than zero: playing ahead of the clicks isn't a delay.
        case measured(Duration)
        /// Too few clicks had a note heard: try again.
        case tooFew(heard: Int)
    }

    /// What is under way at a time, for the screen.
    public enum Progress: Hashable, Sendable {
        /// A count-in beat, from 1.
        case countIn(Int)
        /// One of the clicks played on, from 1.
        case click(Int)
    }

    /// As heard, once known.
    public private(set) var track: ClickTrack
    private var onsets: [Duration] = []

    public init(start: Duration) {
        track = ClickTrack(meter: Meter(.fourFour), bpm: Self.bpm, start: start)
    }

    private var countIn: Int { track.meter.signature.countInClicks }
    private var halfBeat: Duration { .seconds(30) / track.bpm }

    /// When the clicks to play on are heard.
    public var clickTimes: [Duration] { (countIn..<countIn + Self.clicks).map(track.time(ofClick:)) }

    /// Half a beat after the last click: notes after it don't count.
    public var end: Duration { track.time(ofClick: countIn + Self.clicks - 1) + halfBeat }

    /// The answer to asking for the track: when its clicks will be heard.
    public mutating func clicksStarted(_ heard: ClickTrack) { track = heard }

    /// A played note's onset, as the listener reports it.
    public mutating func heard(onset: Duration) { onsets.append(onset) }

    public func progress(at now: Duration) -> Progress? {
        guard now >= track.start, now < end else { return nil }
        let click = track.lastClick(by: now)
        return click < countIn ? .countIn(click + 1) : .click(min(click - countIn, Self.clicks - 1) + 1)
    }

    /// Each click takes the onset nearest it within half a beat either side.
    public var result: Result {
        let window = (.zero - halfBeat)..<halfBeat
        let delays: [Duration] = clickTimes.compactMap { (click: Duration) -> Duration? in
            let near: [Duration] = onsets.map { $0 - click }.filter { window.contains($0) }
            return near.min { max($0, .zero - $0) < max($1, .zero - $1) }
        }
        guard delays.count >= Self.needed else { return .tooFew(heard: delays.count) }
        let sorted = delays.sorted(), middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        return .measured(max(.zero, median))
    }
}
