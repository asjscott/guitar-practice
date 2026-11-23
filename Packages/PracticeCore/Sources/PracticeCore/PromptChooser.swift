import TheoryCore

/// Chooses prompts, or notes, at random from a seed: never the last one again if there is another, and
/// following a weighting if there is one. Shared by every drill.
public struct PromptChooser: Sendable {
    private var random: SplitMix64
    private let weighting: NoteWeighting?

    public init(setup: DrillSetup) {
        random = SplitMix64(seed: setup.seed)
        weighting = setup.weighting
    }

    /// One of `choices`, all alike within a weighting group; nil when there are none.
    public mutating func choose<Choice: Equatable>(from choices: [Choice], avoiding last: Choice?,
                                                   note: (Choice) -> PitchClass) -> Choice? {
        var pool = choices.count > 1 ? choices.filter { $0 != last } : choices
        if let weighting {
            let preferred = pool.filter { weighting.preferred.contains(note($0)) }
            let others = pool.filter { !weighting.preferred.contains(note($0)) }
            if !preferred.isEmpty, !others.isEmpty {
                pool = random.nextFraction() < weighting.share ? preferred : others
            }
        }
        return pool.isEmpty ? nil : pool[Int(random.next() % UInt64(pool.count))]
    }

    public mutating func choose(from prompts: [NotePrompt], avoiding last: NotePrompt?) -> NotePrompt? {
        choose(from: prompts, avoiding: last, note: \.pitchClass)
    }
}

/// A small seeded random number generator, so a seed always gives the same run.
struct SplitMix64: Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func shuffled<Element>(_ elements: [Element]) -> [Element] {
        var elements = elements
        for last in elements.indices.dropFirst().reversed() {
            elements.swapAt(last, Int(next() % UInt64(last + 1)))
        }
        return elements
    }

    /// 0 up to (not including) 1.
    mutating func nextFraction() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
}
