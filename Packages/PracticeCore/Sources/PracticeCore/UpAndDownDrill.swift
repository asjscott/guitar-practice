import TheoryCore

extension DrillKind {
    public static let upAndDown = DrillKind(
        id: "upAndDown", title: "Up and down",
        instructions: "Play up from the lowest root to the top, down to the bottom and back, a note per click. Pick every note.",
        symbol: "chart.line.uptrend.xyaxis", isInSessions: false, rules: UpAndDownRules.self)
}

/// Up and down: passes of one scale through one position, from its lowest root.
public struct UpAndDownRules: PassRules {
    public static var kind: DrillKind { .upAndDown }

    /// With the scale's key, which spells the notes outside it.
    public let setup: DrillSetup
    private let pass: Pass?

    public init(setup: DrillSetup) {
        var setup = setup
        pass = setup.position.flatMap { Pass(through: $0, from: Scale.Degree(1), on: setup.fretboard) }
        setup.key = setup.scale.key
        self.setup = setup
    }

    public var nothingToPromptReason: String? { pass == nil ? DrillSetup.noPositionReason : nil }

    public mutating func nextPass() -> Pass? { pass }

    public func headline(of pass: Pass) -> String { "\(pass.scale.name) · up and down" }
}
