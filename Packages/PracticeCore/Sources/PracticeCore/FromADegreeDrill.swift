import TheoryCore

extension DrillKind {
    public static let fromADegree = DrillKind(
        id: "fromADegree", title: "From a degree",
        instructions: "Play up from the lowest note of the degree named to the top, down to the bottom and back, a note per click. Pick every note.",
        symbol: "chart.line.flattrend.xyaxis", rules: FromADegreeRules.self)
}

/// From a degree: passes through each position in turn, from each of its scale's degrees but the root, each once in a
/// random order before any repeats.
public struct FromADegreeRules: PassRules {
    public static var kind: DrillKind { .fromADegree }

    /// With the scale's key, which spells the notes outside it.
    public let setup: DrillSetup
    private var turns: [Turn]
    private var random: SplitMix64
    /// How many passes there have been.
    private var count = 0

    /// One position's passes.
    private struct Turn: Sendable {
        let passes: [Pass]
        /// Those still to come before any repeats, the next one last.
        var upcoming: [Pass] = []
        var previous: Pass?

        mutating func next(random: inout SplitMix64) -> Pass? {
            if upcoming.isEmpty {
                upcoming = random.shuffled(passes)
                // Not the same one twice in a row.
                if upcoming.count > 1, upcoming.last == previous { upcoming.swapAt(0, upcoming.count - 1) }
            }
            previous = upcoming.popLast()
            return previous
        }
    }

    public init(setup: DrillSetup) {
        self.setup = setup.spelledInScale()
        turns = setup.passPositions.compactMap { position in
            let passes = position.scale.kind.degrees.filter { $0 != Scale.Degree(1) }
                .compactMap { Pass(through: position, from: $0, on: setup.fretboard) }
            return passes.isEmpty ? nil : Turn(passes: passes)
        }
        random = SplitMix64(seed: setup.seed)
    }

    public var nothingToPromptReason: String? { turns.isEmpty ? DrillSetup.noPositionReason : nil }

    public mutating func begin() {
        turns = turns.map { Turn(passes: $0.passes) }
        count = 0
    }

    public mutating func nextPass() -> Pass? {
        guard !turns.isEmpty else { return nil }
        defer { count += 1 }
        return turns[count % turns.count].next(random: &random)
    }

    public func subline(of pass: Pass) -> String { "\(pass.scale.name) · \(pass.position.name)" }

    public func headline(of pass: Pass) -> String {
        "Start on \(pass.startDegree.name) (\(pass.scale.note(at: pass.startDegree)))"
    }
}
