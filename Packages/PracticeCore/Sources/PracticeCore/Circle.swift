import TheoryCore

/// One circle of fifths in a circle drill, finished or not: its time and wrong notes, to set against the best.
public struct CircleResult: Hashable, Sendable {
    /// The prompts' response times added up: the circle's time, but for pauses and skipped prompts.
    public let time: Duration
    public let wrongNotes: Int
    public let skips: Int
    /// Every prompt of every key dealt with: answered, timed out or skipped.
    public let isComplete: Bool

    /// Complete with nothing skipped: only a clean circle can be the best.
    public var isClean: Bool { isComplete && skips == 0 }

    public init(time: Duration, wrongNotes: Int, skips: Int, isComplete: Bool) {
        self.time = time
        self.wrongNotes = wrongNotes
        self.skips = skips
        self.isComplete = isComplete
    }

    /// One attempt of a circle, as the log keeps it.
    public struct Part: Hashable, Sendable {
        /// Tells the circle's groups (one per key) apart.
        public let group: Int
        /// How many attempts the group has; nil when unknown, so that any attempt completes it.
        public let groupSize: Int?
        public let outcome: Attempt.Outcome
        public let responseTime: Duration?
        public let wrongNotes: Int

        public init(group: Int, groupSize: Int?, outcome: Attempt.Outcome, responseTime: Duration?, wrongNotes: Int) {
            self.group = group
            self.groupSize = groupSize
            self.outcome = outcome
            self.responseTime = responseTime
            self.wrongNotes = wrongNotes
        }
    }

    /// From a circle's attempts, as logged: complete when there are `count` groups, each with all its attempts.
    public init(parts: [Part], count: Int = 12) {
        time = parts.reduce(.zero) { $0 + ($1.responseTime ?? .zero) }
        wrongNotes = parts.map(\.wrongNotes).reduce(0, +)
        skips = parts.filter { $0.outcome == .skipped }.count
        let groups = Dictionary(grouping: parts, by: \.group)
        isComplete = groups.count == count && groups.values.allSatisfy { $0.count >= ($0.first?.groupSize ?? 0) }
    }

    /// From one circle's attempts in a run; nil when there are none.
    public init?(attempts: [Attempt], count: Int = 12) {
        guard !attempts.isEmpty else { return nil }
        self.init(parts: attempts.map {
            Part(group: $0.group?.number ?? 0, groupSize: $0.group?.size, outcome: $0.outcome,
                 responseTime: $0.responseTime, wrongNotes: $0.wrongAnswers.count)
        }, count: count)
    }

    /// The fastest clean circle, then the one with fewer wrong notes; nil when none is clean.
    public static func best(of circles: [CircleResult]) -> CircleResult? {
        circles.filter(\.isClean).min { ($0.time, $0.wrongNotes) < ($1.time, $1.wrongNotes) }
    }

    /// Whether this would be the new best over the best so far (nil = none).
    public func isBetter(than best: CircleResult?) -> Bool {
        guard isClean else { return false }
        guard let best, best.isClean else { return true }
        return (time, wrongNotes) < (best.time, best.wrongNotes)
    }
}

/// Where a circle drill has got to, for its header: the key and its place, the clock, the wrong notes and the best.
public struct CircleProgress: Hashable, Sendable {
    /// The circle's keys, from the first.
    public let keys: [Key]
    /// Which key is being played, from 0.
    public let place: Int
    /// Wrong notes so far, the current prompt's included.
    public let wrongNotes: Int
    public let skips: Int
    /// The time taken by what has been dealt with.
    public let elapsed: Duration
    /// While the clock runs: when it last started, on the drill clock. Nil while stopped.
    public let runningSince: Duration?
    /// Once the circle is over.
    public let result: CircleResult?
    /// The best before this run.
    public let best: CircleResult?
    /// What the next key is played in, where it says more than the key: "G shape · down". Nil at the last key.
    public var nextDetail: String?

    public init(keys: [Key], place: Int, wrongNotes: Int, skips: Int, elapsed: Duration, runningSince: Duration?,
                result: CircleResult?, best: CircleResult?) {
        self.keys = keys
        self.place = place
        self.wrongNotes = wrongNotes
        self.skips = skips
        self.elapsed = elapsed
        self.runningSince = runningSince
        self.result = result
        self.best = best
    }

    public var key: Key { keys[place] }
    public var count: Int { keys.count }
    /// Nil at the last key.
    public var next: Key? { place + 1 < keys.count ? keys[place + 1] : nil }

    /// The circle's time so far, `now` on the drill clock.
    public func time(at now: Duration) -> Duration {
        elapsed + (runningSince.map { max(.zero, now - $0) } ?? .zero)
    }

    /// "B · 2 of 12".
    public var placeText: String { "\(key.shortName) · \(place + 1) of \(count)" }
}
