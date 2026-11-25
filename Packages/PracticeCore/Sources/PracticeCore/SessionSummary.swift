/// How a session went: what its summary shows.
public struct SessionSummary: Hashable, Sendable {
    /// A block that started.
    public struct Block: Hashable, Sendable {
        public let kind: DrillKind

        /// Block time, overtime included.
        public let time: Duration
        public let stats: RunStats

        /// In scale blocks only.
        public var passes: PassStats? {
            kind.usesMetronome ? PassStats(PassResult.passes(in: stats.attempts)) : nil
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

    /// Such a session isn't saved.
    public var hasNoAttempts: Bool { blocks.allSatisfy(\.stats.attempts.isEmpty) }

    /// The slowest prompts of every block but the scale blocks: timeouts, then the longest response times.
    public func slowest(_ count: Int) -> [Attempt] {
        RunStats(attempts: blocks.filter { $0.passes == nil }.flatMap(\.stats.attempts)).slowest(count)
    }
}

/// Minutes and seconds, "3:45"; "0:00" when negative. Round up for time that is left.
public func clockText(_ duration: Duration, rounding: FloatingPointRoundingRule = .down) -> String {
    let seconds = max(0, Int((duration / .seconds(1)).rounded(rounding)))
    return "\(seconds / 60):\(seconds % 60 < 10 ? "0" : "")\(seconds % 60)"
}
