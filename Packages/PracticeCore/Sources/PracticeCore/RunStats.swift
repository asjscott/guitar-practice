/// Stats for a run of attempts: for the status bar and the summary at Stop.
public struct RunStats: Hashable, Sendable {
    public let attempts: [Attempt]

    public init(attempts: [Attempt]) {
        self.attempts = attempts
    }

    /// Prompts done (answered or timed out).
    public var prompts: Int { attempts.count }

    /// Attempts whose first played note was right.
    public var firstTryRight: Int { attempts.filter(\.firstRight).count }

    /// First-try right as a fraction 0–1; nil before any prompt is done.
    public var firstTryAccuracy: Double? {
        prompts == 0 ? nil : Double(firstTryRight) / Double(prompts)
    }

    /// The median response time of the answered prompts (timeouts left out); nil if none.
    public var medianResponseTime: Duration? {
        let times = attempts.compactMap(\.responseTime).sorted()
        guard !times.isEmpty else { return nil }
        let middle = times.count / 2
        return times.count.isMultiple(of: 2) ? (times[middle - 1] + times[middle]) / 2 : times[middle]
    }

    /// Prompts that timed out.
    public var timeouts: Int { attempts.filter(\.timedOut).count }

    /// The slowest attempts, slowest first: timeouts (in the order they happened), then the
    /// longest response times. Each keeps its wrong notes for "played E, G first".
    public func slowest(_ count: Int) -> [Attempt] {
        let timedOut = attempts.filter(\.timedOut)
        let answered = attempts.filter { !$0.timedOut }.sorted { $0.responseTime! > $1.responseTime! }
        return Array((timedOut + answered).prefix(count))
    }
}

extension NotePlayItDrill {
    /// Stats for this run's attempts so far.
    public var stats: RunStats { RunStats(attempts: attempts) }
}
