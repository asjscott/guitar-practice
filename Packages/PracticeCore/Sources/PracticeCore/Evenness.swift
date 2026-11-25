extension PassResult {
    /// The times between onsets; nil unless every note was played, with none wrong.
    var gaps: [Duration]? {
        guard isComplete, attempts.allSatisfy(\.firstRight) else { return nil }
        return attempts.dropFirst().compactMap(\.responseTime)
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
