/// How a scale block's passes went. Only complete ones count.
public struct PassStats: Hashable, Sendable {
    public let passes: Int
    public let cleanPasses: Int

    /// BPM; nil if none was clean.
    public let fastestCleanTempo: Int?

    /// Of the passes that have one; nil if none has.
    public let medianEvenness: Duration?

    public init(_ results: [PassResult]) {
        let complete = results.filter(\.isComplete), clean = complete.filter(\.isClean)
        passes = complete.count
        cleanPasses = clean.count
        fastestCleanTempo = clean.compactMap(\.tempo).max()
        medianEvenness = median(of: complete.compactMap(\.evenness))
    }
}

extension PassResult {
    /// BPM.
    fileprivate var tempo: Int? {
        if case .pass(let facts) = attempts.first?.facts { facts.tempo } else { nil }
    }
}

// Text for the summary.
extension PassStats {
    /// Clean passes out of all: "6 of 9"; "–" without passes.
    public var cleanText: String { passes == 0 ? "–" : "\(cleanPasses) of \(passes)" }

    /// "clean at 76 BPM", the fastest; nil if none was clean.
    public var tempoText: String? { fastestCleanTempo.map { "clean at \($0) BPM" } }

    /// "9 passes · 6 clean", and under it "evenness 24 ms" if there is one.
    public var detailText: String {
        let counts = "\(passes) \(passes == 1 ? "pass" : "passes") · \(cleanPasses) clean"
        return [counts, medianEvenness.map(PassResult.evennessText)].compactMap { $0 }.joined(separator: "\n")
    }
}
