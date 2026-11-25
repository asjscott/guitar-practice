/// Moves a scale drill's tempo as passes are played.
public struct TempoLadder: Hashable, Sendable {
    /// BPM.
    public static let step = 4

    /// Complete passes in a row that weren't clean, since they last took the tempo down.
    private var notClean = 0

    public init() {}

    /// What a pass adds to the tempo: 4 if it was clean and kept up; 4 off after two in a row that weren't clean. One
    /// cut short counts neither way.
    public mutating func step(after pass: PassResult) -> Int {
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
    /// The times between onsets; nil unless every note was played, with none wrong.
    private var gaps: [Duration]? {
        guard isComplete, attempts.allSatisfy(\.firstRight) else { return nil }
        return attempts.dropFirst().compactMap(\.responseTime)
    }

    /// Whether it took, from first to last onset, at most a tenth more than its clicks did.
    var keptUp: Bool {
        guard let gaps, case .pass(let facts) = attempts.first?.facts else { return false }
        let time = gaps.reduce(.zero, +)
        return time * 10 * facts.tempo <= .seconds(60) * 11 * gaps.count
    }

    /// The standard deviation of the gaps between onsets; nil unless every note was played, with none wrong.
    public var evenness: Duration? {
        guard let gaps, !gaps.isEmpty else { return nil }
        let seconds = gaps.map { $0 / .seconds(1) }
        let mean = seconds.reduce(0, +) / Double(seconds.count)
        let variance = seconds.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(seconds.count)
        return .seconds(variance.squareRoot())
    }
}

extension PassResult {
    /// "evenness 18 ms".
    static func evennessText(_ evenness: Duration) -> String {
        "evenness \(Int((evenness / .milliseconds(1)).rounded())) ms"
    }
}

extension PassProgress {
    /// "evenness 18 ms".
    public var evennessText: String? { evenness.map(PassResult.evennessText) }
}

extension PassSettings {
    public static let tempos = 40...160

    /// "♩ = 72 · 4/4": the note is the one that makes a click.
    public var text: String { "\(meter.signature.unit == 8 ? "♪" : "♩") = \(tempo) · \(meter.signature.name)" }
}
