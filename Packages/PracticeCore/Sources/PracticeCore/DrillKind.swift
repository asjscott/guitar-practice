/// A drill the app offers. The Drill screen's picker and the session planner read `all`.
///
/// To add a drill: write its `DrillRules` in its own file, with a `static let` for its kind in an extension
/// of `DrillKind`, and add that kind to `all`.
public struct DrillKind: Identifiable, Sendable {
    /// Every drill, in the picker's order.
    public static let all: [DrillKind] = [
        .notePlayIt,
        .allInstances,
        .hearFindIt,
        .fretNameIt,
    ]

    /// Saved in the attempt log: never change it.
    public let id: String

    public let module: DrillModule

    /// "Note → play it".
    public let title: String

    /// How to play it, in one sentence.
    public let instructions: String

    /// An SF Symbol name.
    public let symbol: String

    /// Answered by typing rather than on the guitar.
    public let usesKeyboard: Bool

    /// Can't run without sound output.
    public let needsSound: Bool

    /// The note isn't shown while it is prompted, so a skip must not show it either.
    public let hidesNote: Bool

    /// Whether sessions use it; one that isn't is for free practice only.
    public let isInSessions: Bool

    /// Whether "In order (check)" applies to it.
    public let offersOrder: Bool

    /// What R does, as a button title ("Replay"); nil = nothing.
    public let repeatTitle: String?

    private let make: @Sendable (DrillSetup) -> any Drill

    public init<Rules: DrillRules>(id: String, module: DrillModule, title: String, instructions: String, symbol: String,
                                   usesKeyboard: Bool = false, needsSound: Bool = false, hidesNote: Bool = false,
                                   isInSessions: Bool = true, offersOrder: Bool = false, repeatTitle: String? = nil, rules: Rules.Type) {
        self.id = id
        self.module = module
        self.title = title
        self.instructions = instructions
        self.symbol = symbol
        self.usesKeyboard = usesKeyboard
        self.needsSound = needsSound
        self.hidesNote = hidesNote
        self.isInSessions = isInSessions
        self.offersOrder = offersOrder
        self.repeatTitle = repeatTitle
        make = { PromptDrill<Rules>(setup: $0) }
    }

    /// A new drill of this kind, idle. Order is dropped from the options where the kind doesn't offer it.
    public func makeDrill(_ setup: DrillSetup) -> any Drill {
        var setup = setup
        if !offersOrder { setup.options.order = .random }
        return make(setup)
    }
}

extension DrillKind: Hashable {
    public static func == (a: DrillKind, b: DrillKind) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
