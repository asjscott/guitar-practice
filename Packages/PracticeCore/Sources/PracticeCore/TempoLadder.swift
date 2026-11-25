/// Moves a scale drill's tempo as passes are played.
public struct TempoLadder: Hashable, Sendable {
    /// BPM.
    public static let step = 4

    /// Complete passes in a row that weren't clean, since they last took the tempo down.
    private var notClean = 0

    public init() {}

    /// What a pass adds to the tempo: 4 if it was clean and kept up; 4 off after two in a row that weren't clean. One
    /// cut short counts neither way.
    public mutating func change(after pass: PassResult) -> Int {
        guard pass.isComplete else { return 0 }
        if pass.isClean {
            notClean = 0
            return pass.keptUp ? Self.step : 0
        }
        notClean += 1
        guard notClean == 2 else { return 0 }
        notClean = 0
        return -Self.step
    }
}

extension PassResult {
    /// Whether it took, from first to last onset, at most a tenth more than its clicks did.
    var keptUp: Bool {
        guard let gaps, case .pass(let facts) = attempts.first?.facts else { return false }
        let time = gaps.reduce(.zero, +)
        return time * 10 * facts.tempo <= .seconds(60) * 11 * gaps.count
    }
}
