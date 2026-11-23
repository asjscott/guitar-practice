/// A drill a session can use, and its share of the time relative to the others.
public struct WeightedDrill: Hashable, Sendable {
    public let kind: DrillKind
    public let weight: Double

    /// A weight of zero or less leaves the drill out.
    public init(_ kind: DrillKind, weight: Double = 1) {
        self.kind = kind
        self.weight = weight
    }
}

/// A planned block: one drill and how long it is meant to last.
public struct SessionBlock: Hashable, Sendable {
    public let kind: DrillKind
    public let length: Duration

    public init(kind: DrillKind, length: Duration) {
        self.kind = kind
        self.length = length
    }
}

/// Splits a session's time into blocks.
public enum SessionPlanner {
    /// No block is shorter, unless there is only one.
    public static let minimumLength: Duration = .seconds(180)

    /// One block per drill, with time by weight; drills are dropped, a different one each day, until every block
    /// reaches the minimum. `day` is a count of calendar days: it seeds the order and says which drill is dropped.
    public static func plan(_ drills: [WeightedDrill], budget: Duration, day: Int) -> [SessionBlock] {
        let drills = drills.filter { $0.weight > 0 }
        guard !drills.isEmpty else { return [] }
        let first = (day % drills.count + drills.count) % drills.count
        var kept = Array(drills[first...] + drills[..<first])
        var blocks = shares(of: budget, among: kept)
        while kept.count > 1, blocks.contains(where: { $0.length < minimumLength }) {
            kept.removeFirst()
            blocks = shares(of: budget, among: kept)
        }
        // Back in the given order, so that the shuffle doesn't follow the rotation.
        let inOrder = drills.compactMap { drill in blocks.first { $0.kind == drill.kind } }
        return shuffled(inOrder, day: day)
    }

    private static func shares(of budget: Duration, among drills: [WeightedDrill]) -> [SessionBlock] {
        let total = drills.map(\.weight).reduce(0, +)
        let milliseconds = budget / .milliseconds(1)
        return drills.map {
            SessionBlock(kind: $0.kind, length: .milliseconds(Int((milliseconds * $0.weight / total).rounded())))
        }
    }

    /// Any drill that uses the keyboard is first or last, so that the player changes between keyboard and guitar at
    /// most once.
    private static func shuffled(_ blocks: [SessionBlock], day: Int) -> [SessionBlock] {
        var random = SplitMix64(seed: UInt64(bitPattern: Int64(day)))
        var blocks = blocks
        for last in blocks.indices.dropFirst().reversed() {
            blocks.swapAt(last, Int(random.next() % UInt64(last + 1)))
        }
        let keyboard = blocks.filter(\.kind.usesKeyboard)
        let guitar = blocks.filter { !$0.kind.usesKeyboard }
        return random.next().isMultiple(of: 2) ? keyboard + guitar : guitar + keyboard
    }
}
