import TheoryCore

/// What a pass is played at. Changing it takes effect from the next pass on.
public struct PassSettings: Hashable, Sendable {
    /// BPM, counting clicks; kept within `tempos`.
    public var tempo = 60 {
        didSet { tempo = min(max(tempo, Self.tempos.lowerBound), Self.tempos.upperBound) }
    }
    /// Turns the tempo ladder off.
    public var holdsTempo = false
    public var meter = Meter(.fourFour)
    /// Nil follows the stage reached (`DrillSetup.fadeStages`).
    public var fadeStage: FadeStage?

    public init() {}
}

/// One scale through a position, in the order it is played.
public struct Pass: Hashable, Sendable {
    public let position: Position
    public let startDegree: Scale.Degree
    public let locations: [FretboardLocation]

    /// Nil if the position lacks the degree.
    public init?(through position: Position, from startDegree: Scale.Degree, on fretboard: Fretboard) {
        guard let locations = fretboard.passOrder(of: position, from: startDegree) else { return nil }
        self.position = position
        self.startDegree = startDegree
        self.locations = locations
    }

    public var scale: Scale { position.scale }
}

/// What makes one scale drill different from another. `PassDrill` does the rest.
public protocol PassRules: Sendable {
    static var kind: DrillKind { get }

    init(setup: DrillSetup)

    var setup: DrillSetup { get }

    /// Why there is no pass to play, if so.
    var nothingToPromptReason: String? { get }

    /// A run is starting. Default: nothing.
    mutating func begin()

    /// The next pass; nil ends the run.
    mutating func nextPass() -> Pass?

    /// "A major · up and down".
    func headline(of pass: Pass) -> String

    /// Next to the headline. Default: the position's name.
    func subline(of pass: Pass) -> String
}

extension PassRules {
    public mutating func begin() {}
    public func subline(of pass: Pass) -> String { pass.position.name }
}

extension DrillSetup {
    /// The chosen scale on the key's tonic.
    public var scale: Scale { Scale(options.scaleKind, in: key ?? options.key) }

    /// The positions of the chosen scale, up the neck.
    public var positions: [Position] { fretboard.positions(of: scale, system: options.positionSystem) }

    /// The chosen position, or its lowest placement. Where the scale has no positions of the chosen one's system, the
    /// first. Nil when that doesn't fit the neck.
    public var position: Position? {
        let id = options.position, positions = positions
        return positions.first { $0.id == id }
            ?? positions.first { $0.system == id.system && $0.number == id.number && $0.octave == 0 }
            ?? positions.first { $0.system != id.system && $0.number == 1 && $0.octave == 0 }
    }

    /// The positions passes take turns through, a pass each: the chosen one, or with a theme, one for each scale of its
    /// mode, in or near its position. Empty when there are none on the neck.
    public var passPositions: [Position] {
        guard let theme else { return [position].compactMap { $0 } }
        guard let position = theme.position(on: fretboard) else { return [] }
        return theme.key.mode.practisedScales.compactMap {
            fretboard.position(of: Scale($0, in: theme.key), nearest: position)
        }
    }

    static let noPositionReason = "The position doesn’t fit on this neck."
}

extension Key.Mode {
    /// The scales a session goes through, in order.
    fileprivate var practisedScales: [Scale.Kind] {
        switch self {
        case .major: [.major, .majorPentatonic]
        case .minor: [.naturalMinor, .minorPentatonic, .blues]
        }
    }
}

/// How one pass went, from its attempts.
public struct PassResult: Hashable, Sendable {
    /// In order.
    public let attempts: [Attempt]

    /// Every note was played or revealed.
    public var isComplete: Bool {
        attempts.count == attempts.first?.group?.size && !attempts.contains(where: \.skipped)
    }

    /// Complete, with no wrong note, timeout or hint.
    public var isClean: Bool { isComplete && attempts.allSatisfy { $0.firstRight && !wasHinted($0) } }

    private func wasHinted(_ attempt: Attempt) -> Bool {
        if case .pass(let facts) = attempt.facts { facts.hinted } else { false }
    }

    /// "Clean pass", "Pass done · 2 wrong · 1 revealed".
    public var text: String {
        isClean ? "Clean pass" : (["Pass done"] + mistakes).joined(separator: " · ")
    }

    /// "Last pass: clean", "Last pass: 2 wrong · 1 revealed".
    var lastPassText: String {
        "Last pass: " + (isClean ? "clean" : mistakes.isEmpty ? "done" : mistakes.joined(separator: " · "))
    }

    /// Notes with a wrong answer first, notes revealed, and whether a hint was used.
    private var mistakes: [String] {
        let wrong = attempts.filter { !$0.wrongAnswers.isEmpty }.count
        let revealed = attempts.filter(\.timedOut).count
        return (wrong > 0 ? ["\(wrong) wrong"] : []) + (revealed > 0 ? ["\(revealed) revealed"] : [])
            + (attempts.contains(where: wasHinted) ? ["hint used"] : [])
    }

    /// The passes among a run's attempts, oldest first.
    public static func passes(in attempts: [Attempt]) -> [PassResult] {
        var groups: [(number: Int, attempts: [Attempt])] = []
        for attempt in attempts {
            guard case .pass = attempt.facts, let number = attempt.group?.number else { continue }
            if groups.last?.number == number {
                groups[groups.count - 1].attempts.append(attempt)
            } else {
                groups.append((number, [attempt]))
            }
        }
        return groups.map { PassResult(attempts: $0.attempts) }
    }
}

extension Drill {
    /// The run's passes that have attempts, oldest first; none in drills without passes.
    public var passes: [PassResult] { PassResult.passes(in: attempts) }
}

/// A pass as it goes: a line that rises and falls with pitch and fills in.
public struct PassProgress: Hashable, Sendable {
    public struct Note: Hashable, Sendable {
        /// From the lowest pitch (0) to the highest (1).
        public var height: Double
        public var state: DrillDisplay.Chip.State
    }

    public var notes: [Note]

    /// The beat of the bar being counted in; nil once the pass goes, and before the first click is heard.
    public var countIn: Int?

    /// The evenness of the pass just over: until the next pass's count-in ends.
    public var evenness: Duration?

    public var settings: PassSettings

    /// The frets to show.
    public var fretWindow: ClosedRange<Int>
}
