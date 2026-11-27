/// How a session went: what its summary shows.
public struct SessionSummary: Hashable, Sendable {
    /// A block that started.
    public struct Block: Hashable, Sendable {
        public let kind: DrillKind
        /// Its place in the session's blocks, from 0.
        public let step: Int

        /// Block time, overtime included.
        public let time: Duration
        public let stats: RunStats
        /// In circle blocks: the best before the session, on its tuning and capo; nil before there was one.
        public let circleBest: CircleResult?

        /// In circle blocks: the circle as far as it went; nil before any prompt was dealt with.
        public var circle: CircleResult? {
            kind.goesRoundTheCircle ? CircleResult(attempts: stats.attempts) : nil
        }

        /// How it went, for the rail: "9:12 · 1 wrong", "24 of 27 right · 2.1 s each", "4 passes · 3 clean · 92 BPM",
        /// "28 of 32 chords clean · 6:10"; or the time spent, "6:00".
        public var resultText: String {
            if let circle { return circle.summaryText + (circle.isComplete ? "" : " · not finished") }
            if let passes, passes.passes > 0 {
                let counts = "\(passes.passes) \(passes.passes == 1 ? "pass" : "passes") · \(passes.cleanPasses) clean"
                return counts + (passes.fastestCleanTempo.map { " · \($0) BPM" } ?? "")
            }
            if let chords, chords.chords > 0 { return "\(chords.clean) of \(chords.chords) chords clean · \(time.clockText)" }
            guard !kind.hasNoPrompts, !kind.hasPasses, stats.prompts > 0 else { return time.clockText }
            let right = "\(stats.firstTryRight) of \(stats.prompts) right"
            return right + ((kind.module == .triads ? medianVoicingTime : stats.medianResponseTime)
                .map { " · \(secondsText($0, decimals: 1)) s each" } ?? "")
        }

        /// In scale blocks only.
        public var passes: PassStats? {
            kind.hasPasses ? PassStats(PassResult.passes(in: stats.attempts)) : nil
        }

        /// In progression blocks only.
        public var chords: ChordSummary? {
            kind.module == .progressions && !kind.hasNoPrompts ? ChordSummary(attempts: stats.attempts) : nil
        }

        /// In triad blocks only.
        public var medianVoicingTime: Duration? { kind.module == .triads ? stats.medianVoicingTime : nil }

        /// The median response time, "1.24 s", or in triad blocks the median time per voicing, "3.10 s a voicing"; nil
        /// where there is none.
        public var speedText: String? {
            if kind.module == .triads { return medianVoicingTime.map { "\(secondsText($0, decimals: 2)) s a voicing" } }
            return stats.medianResponseTime == nil ? nil : stats.medianText
        }
    }

    /// Ready cards included.
    public let totalTime: Duration

    /// Blocks that started, in order.
    public let blocks: [Block]

    /// How many blocks the session had, those left out included.
    public let steps: Int

    /// Ended before its last block was over.
    public let endedEarly: Bool

    /// The fade levels that moved in the session, from before it to the end.
    public let fadeMoves: [FadeMove]

    /// The circle blocks that were played.
    public var circles: [Block] { blocks.filter { $0.circle != nil } }

    /// The Scale circle's keys and their times, in the order played; empty without one.
    public var scaleCircleKeys: [CircleKeyTime] {
        blocks.first { $0.kind == .scaleCircle }.map { CircleKeyTime.times(in: $0.stats.attempts) } ?? []
    }

    /// "41 minutes, every step", "38 minutes, 5 of 8 steps", "12 minutes, ended early".
    public var headline: String {
        let minutes = max(1, Int((totalTime / .seconds(60)).rounded()))
        let time = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        if endedEarly { return time + ", ended early" }
        return time + (blocks.count == steps ? ", every step" : ", \(blocks.count) of \(steps) steps")
    }

    /// Such a session isn't saved.
    public var hasNoAttempts: Bool { blocks.allSatisfy(\.stats.attempts.isEmpty) }

    /// The slowest prompts of every block but the scale and progression blocks: timeouts, then the longest response
    /// times.
    public func slowest(_ count: Int) -> [Attempt] {
        RunStats(attempts: blocks.filter { $0.passes == nil && $0.chords == nil }.flatMap(\.stats.attempts)).slowest(count)
    }
}

/// Minutes and seconds, "3:45"; "0:00" when negative. Round up for time that is left.
public func clockText(_ duration: Duration, rounding: FloatingPointRoundingRule = .down) -> String {
    let seconds = max(0, Int((duration / .seconds(1)).rounded(rounding)))
    return "\(seconds / 60):\(seconds % 60 < 10 ? "0" : "")\(seconds % 60)"
}
