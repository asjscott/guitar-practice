import TheoryCore

/// How a progression drill's chords went: for the summary at the end of a run or block.
public struct ChordSummary: Hashable, Sendable {
    /// A chord of the progression and how often it was clean.
    public struct Chord: Hashable, Sendable {
        /// "Em".
        public let name: String
        public let clean: Int
        public let played: Int

        /// "Em (4 of 10)".
        public var text: String { "\(name) (\(clean) of \(played))" }
    }

    /// Chords scored.
    public let chords: Int
    public let clean: Int
    /// Times through played to the end.
    public let timesThrough: Int
    /// The first of those played at Hidden, from 1; nil if none was.
    public let firstHidden: Int?
    /// At most two that weren't always clean, fewest clean first (in order of the progression when tied).
    public let hardest: [Chord]

    public init(attempts: [Attempt]) {
        let chords = attempts.compactMap { attempt in attempt.chord.map { (attempt.group, $0) } }
        self.chords = chords.count
        clean = chords.filter { $0.1.outcome == .clean }.count
        var groups: [(number: Int, facts: [ChordFacts], size: Int)] = []
        for (group, facts) in chords {
            guard let group else { continue }
            if groups.last?.number == group.number { groups[groups.count - 1].facts.append(facts) }
            else { groups.append((group.number, [facts], group.size ?? 0)) }
        }
        let complete = groups.filter { $0.facts.count == $0.size }
        timesThrough = complete.count
        firstHidden = complete.firstIndex { $0.facts.first?.fadeStage == .hidden }.map { $0 + 1 }
        var byChord: [(name: String, clean: Int, played: Int, place: Int)] = []
        for (_, facts) in chords {
            let name = facts.triad.shortName
            if let index = byChord.firstIndex(where: { $0.name == name }) {
                byChord[index].played += 1
                if facts.outcome == .clean { byChord[index].clean += 1 }
            } else {
                byChord.append((name, facts.outcome == .clean ? 1 : 0, 1, facts.place))
            }
        }
        hardest = byChord.filter { $0.clean < $0.played }
            .sorted { ($0.clean * $1.played, $0.place) < ($1.clean * $0.played, $1.place) }
            .prefix(2).map { Chord(name: $0.name, clean: $0.clean, played: $0.played) }
    }

    /// "31 of 40 chords clean · 10 times through · Hidden from the 5th".
    public var text: String {
        var parts = ["\(clean) of \(chords) chords clean",
                     "\(timesThrough) \(timesThrough == 1 ? "time" : "times") through"]
        if let firstHidden { parts.append("Hidden from the \(firstHidden.ordinal)") }
        return parts.joined(separator: " · ")
    }
}
