import TheoryCore

extension DrillKind {
    public static let fromADegree = DrillKind(
        id: "fromADegree", title: "From a degree",
        instructions: "Play up from the lowest note of the degree named to the top, down to the bottom and back, a note per click. Pick every note.",
        symbol: "chart.line.flattrend.xyaxis", isInSessions: false, rules: FromADegreeRules.self)
}

/// From a degree: passes of one scale through one position, from each of its degrees but the root, each once in a random
/// order before any repeats.
public struct FromADegreeRules: PassRules {
    public static var kind: DrillKind { .fromADegree }

    /// With the scale's key, which spells the notes outside it.
    public let setup: DrillSetup
    private let passes: [Pass]
    private var random: SplitMix64
    /// Those still to come before any repeats, the next one last.
    private var upcoming: [Pass] = []
    private var previous: Pass?

    public init(setup: DrillSetup) {
        var setup = setup
        let scale = setup.scale, fretboard = setup.fretboard
        passes = setup.position.map { position in
            scale.kind.degrees.filter { $0 != Scale.Degree(1) }.compactMap { Pass(through: position, from: $0, on: fretboard) }
        } ?? []
        random = SplitMix64(seed: setup.seed)
        setup.key = scale.key
        self.setup = setup
    }

    public var nothingToPromptReason: String? { passes.isEmpty ? DrillSetup.noPositionReason : nil }

    public mutating func begin() {
        upcoming = []
        previous = nil
    }

    public mutating func nextPass() -> Pass? {
        if upcoming.isEmpty {
            upcoming = random.shuffled(passes)
            // Not the same one twice in a row.
            if upcoming.count > 1, upcoming.last == previous { upcoming.swapAt(0, upcoming.count - 1) }
        }
        previous = upcoming.popLast()
        return previous
    }

    public func headline(of pass: Pass) -> String {
        let degree = pass.startDegree
        let note = pass.scale.spell(pass.scale.tonic.pitchClass + degree.interval)
        return "Start on \(degree.name) (\(note))"
    }
}
