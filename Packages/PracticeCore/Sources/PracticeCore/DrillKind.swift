/// A drill the app offers. The Drill screen's picker and the session planner read `all`.
///
/// To add a drill: write its `DrillRules` (a scale drill's `PassRules`) in its own file, with a `static let` for its kind in an extension
/// of `DrillKind`, and add that kind to `all`.
public struct DrillKind: Identifiable, Sendable {
    /// Every drill, in the picker's order.
    public static let all: [DrillKind] = [
        .notePlayIt,
        .allInstances,
        .noteCircle,
        .hearFindIt,
        .fretNameIt,
        .upAndDown,
        .fromADegree,
        .triadPlayIt,
        .inversions,
        .triadCircle,
        .nearestVoicing,
        .stayInPosition,
        .targetTopNote,
        .chordsInPosition,
        .freeTime,
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

    /// What sets a drill apart from most.
    public struct Traits: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let usesKeyboard = Traits(rawValue: 1 << 0)
        public static let needsSound = Traits(rawValue: 1 << 1)
        public static let hidesNote = Traits(rawValue: 1 << 2)
        public static let offersOrder = Traits(rawValue: 1 << 3)
        public static let offersInversions = Traits(rawValue: 1 << 4)
        public static let hasPasses = Traits(rawValue: 1 << 5)
        public static let hasClimbs = Traits(rawValue: 1 << 6)
        public static let hasBacking = Traits(rawValue: 1 << 7)
        public static let goesRoundTheCircle = Traits(rawValue: 1 << 8)
        public static let hasNoPrompts = Traits(rawValue: 1 << 9)
    }

    private let traits: Traits

    /// Answered by typing rather than on the guitar.
    public var usesKeyboard: Bool { traits.contains(.usesKeyboard) }

    /// Can't run without sound output.
    public var needsSound: Bool { traits.contains(.needsSound) }

    /// The note isn't shown while it is prompted, so a skip must not show it either.
    public var hidesNote: Bool { traits.contains(.hidesNote) }

    /// Whether "In order (check)" applies to it.
    public var offersOrder: Bool { traits.contains(.offersOrder) }

    /// Whether the player chooses its inversions.
    public var offersInversions: Bool { traits.contains(.offersInversions) }

    /// A scale drill: passes, played to the metronome at a tempo of its own.
    public var hasPasses: Bool { traits.contains(.hasPasses) }

    /// What it shows fades as it is learned, and H shows it.
    public var fades: Bool { (hasPasses || module == .triads || module == .progressions) && !hasNoPrompts }

    /// Plays backing: a progression drill over it, round and round the progression, or Free time.
    public var hasBacking: Bool { traits.contains(.hasBacking) }

    /// Asks nothing and logs nothing: Free time.
    public var hasNoPrompts: Bool { traits.contains(.hasNoPrompts) }

    /// A circle drill: once round the circle of fifths from the key, against the best (`CircleProgress`).
    public var goesRoundTheCircle: Bool { traits.contains(.goesRoundTheCircle) }

    /// Its prompts are climbs.
    public var hasClimbs: Bool { traits.contains(.hasClimbs) }

    /// What R does, as a button title ("Replay"); nil = nothing.
    public let repeatTitle: String?

    private let make: @Sendable (DrillSetup) -> any Drill

    public init<Rules: DrillRules>(id: String, module: DrillModule, title: String, instructions: String, symbol: String,
                                   traits: Traits = [], repeatTitle: String? = nil, rules: Rules.Type) {
        self.init(id: id, module: module, title: title, instructions: instructions, symbol: symbol, traits: traits,
                  repeatTitle: repeatTitle) { PromptDrill<Rules>(setup: $0) }
    }

    /// A scale drill.
    public init<Rules: PassRules>(id: String, title: String, instructions: String, symbol: String, rules: Rules.Type) {
        self.init(id: id, module: .scales, title: title, instructions: instructions, symbol: symbol, traits: .hasPasses,
                  repeatTitle: "Restart") { PassDrill<Rules>(setup: $0) }
    }

    /// A progression drill.
    public init<Rules: ProgressionRules>(id: String, title: String, instructions: String, symbol: String,
                                         rules: Rules.Type) {
        self.init(id: id, module: .progressions, title: title, instructions: instructions, symbol: symbol,
                  traits: .hasBacking, repeatTitle: nil) { ProgressionDrill<Rules>(setup: $0) }
    }

    /// A drill with an engine of its own.
    init(id: String, module: DrillModule, title: String, instructions: String, symbol: String, traits: Traits,
         repeatTitle: String?, make: @escaping @Sendable (DrillSetup) -> any Drill) {
        self.id = id
        self.module = module
        self.title = title
        self.instructions = instructions
        self.symbol = symbol
        self.traits = traits
        self.repeatTitle = repeatTitle
        self.make = make
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
