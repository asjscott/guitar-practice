import TheoryCore

extension DrillKind {
    public static let upAndDown = DrillKind(
        id: "upAndDown", title: "Up and down",
        instructions: "Play up from the lowest root to the top, down to the bottom and back, a note per click. Pick every note.",
        symbol: "chart.line.uptrend.xyaxis", rules: UpAndDownRules.self)
}

/// Up and down: passes through each position in turn, from its lowest root.
public struct UpAndDownRules: PassRules {
    public static var kind: DrillKind { .upAndDown }

    /// With the scale's key, which spells the notes outside it.
    public let setup: DrillSetup
    private let passes: [Pass]
    /// How many passes there have been.
    private var count = 0

    public init(setup: DrillSetup) {
        var setup = setup
        let fretboard = setup.fretboard
        passes = setup.passPositions.compactMap { Pass(through: $0, from: Scale.Degree(1), on: fretboard) }
        if let scale = passes.first?.scale { setup.key = scale.key }
        self.setup = setup
    }

    public var nothingToPromptReason: String? { passes.isEmpty ? DrillSetup.noPositionReason : nil }

    public mutating func begin() { count = 0 }

    public mutating func nextPass() -> Pass? {
        guard !passes.isEmpty else { return nil }
        defer { count += 1 }
        return passes[count % passes.count]
    }

    public func headline(of pass: Pass) -> String { "\(pass.scale.name) · up and down" }
}
