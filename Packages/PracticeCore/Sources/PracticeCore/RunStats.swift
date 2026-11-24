/// Stats for a run of attempts: for the status bar and the summary at Stop.
public struct RunStats: Hashable, Sendable {
    public let attempts: [Attempt]

    public init(attempts: [Attempt]) {
        self.attempts = attempts
    }

    /// The attempts that count: answered or timed out.
    private var done: [Attempt] { attempts.filter { !$0.skipped } }

    /// Prompts done (answered or timed out). A sweep is one, as soon as it has an attempt, and a triad as soon as one of
    /// its notes is done; everything else here is per attempt.
    public var prompts: Int {
        let counted = attempts.filter { !$0.skipped || $0.prompt.sweep != nil }
        return Set(counted.compactMap(\.group?.number)).count + counted.filter { $0.group == nil }.count
    }

    /// Attempts skipped. They count in nothing else.
    public var skips: Int { attempts.filter(\.skipped).count }

    /// Attempts whose first answer was right.
    public var firstTryRight: Int { attempts.filter(\.firstRight).count }

    /// First-try right as a fraction 0–1; nil before any is done.
    public var firstTryAccuracy: Double? {
        done.isEmpty ? nil : Double(firstTryRight) / Double(done.count)
    }

    /// The median response time of the answered attempts (timeouts and skips left out); nil if none.
    public var medianResponseTime: Duration? {
        let times = attempts.compactMap(\.responseTime).sorted()
        guard !times.isEmpty else { return nil }
        let middle = times.count / 2
        return times.count.isMultiple(of: 2) ? (times[middle - 1] + times[middle]) / 2 : times[middle]
    }

    /// Attempts that timed out.
    public var timeouts: Int { attempts.filter(\.timedOut).count }

    /// The slowest attempts, slowest first: timeouts (in the order they happened), then the
    /// longest response times. Each keeps its wrong answers for "played E, G first".
    public func slowest(_ count: Int) -> [Attempt] {
        let timedOut = attempts.filter(\.timedOut)
        let answered = attempts.filter { $0.responseTime != nil }
            .sorted { ($0.responseTime ?? .zero) > ($1.responseTime ?? .zero) }
        return Array((timedOut + answered).prefix(count))
    }
}
