import TheoryCore

/// What a drill can prompt, chosen before a run and fixed while it goes.
public struct DrillOptions: Hashable, Sendable {
    /// Which notes are prompted. "In order (check)" ignores it.
    public enum Notes: Hashable, Sendable {
        /// C D E F G A B only.
        case naturals
        /// All twelve.
        case all
    }

    /// The order of prompts, for drills that offer it.
    public enum Order: Hashable, Sendable {
        /// Random, never the same prompt twice in a row.
        case random
        /// "In order (check)": every location in range once, string 6 first, fret by fret.
        case inOrder
    }

    /// The two fret ranges offered in the toolbar.
    public static let fretRanges: [ClosedRange<Int>] = [0...12, 0...22]

    public var notes: Notes = .naturals

    /// Frets counted from the nut. Frets below the capo are never prompted.
    public var frets: ClosedRange<Int> = 0...12

    /// Included strings as internal indices (0 = string 6); nil = every string.
    public var strings: Set<Int>? = nil

    public var order: Order = .random

    /// What drills built on a key use when the setup has none.
    public var key: Key = .major(.c)

    /// Triads only.
    public var stringSets = Set(StringSet.allCases)

    /// Triads only.
    public var inversions = Set(Triad.Inversion.allCases)

    /// Triads only: what they are played at; nil follows the stage reached (`DrillSetup.fadeStages`).
    public var triadFade: FadeStage?

    /// Scales only. The key moves to its mode.
    public var scaleKind: Scale.Kind = .major

    /// Scales only: which positions there are to choose from.
    public var positionSystem: Position.System = .caged

    /// Scales only. One that isn't there falls back (`DrillSetup.position`).
    public var position = Position.ID(system: .caged, number: CAGEDShape.e.number)

    /// Scales only: what passes are played at, at first.
    public var pass = PassSettings()

    /// Progressions only: what is played, in the key, and in the position of the key's scale. Nil = none chosen yet,
    /// so progression drills have nothing to prompt.
    public var progression: Progression?

    /// Progressions only: how the backing is played.
    public var backing = BackingSettings()

    public init() {}
}

/// How a progression drill's backing is played.
public struct BackingSettings: Hashable, Sendable {
    public static let defaultTempo = 70

    public var style = BackingStyle.rock
    /// BPM.
    public var tempo = defaultTempo

    public init(style: BackingStyle = .rock, tempo: Int = defaultTempo) {
        self.style = style
        self.tempo = tempo
    }
}

/// Notes to ask for more often, such as the theme key's.
public struct NoteWeighting: Hashable, Sendable {
    public let preferred: Set<PitchClass>

    /// How often a preferred note is chosen, 0–1, when there are both preferred and other notes to choose from.
    public let share: Double

    public init(preferred: Set<PitchClass>, share: Double) {
        self.preferred = preferred
        self.share = share
    }
}

/// Everything a drill is made from.
public struct DrillSetup: Hashable, Sendable {
    public var fretboard: Fretboard
    public var options: DrillOptions

    /// The key prompts are spelled in; nil = sharps.
    public var key: Key?

    /// Notes to ask for more often; nil = all alike.
    public var weighting: NoteWeighting?

    /// Taken off every onset before it is compared with clicks or backing, in passes and progression drills (see
    /// "Input delay" in GLOSSARY.md). The input device's, measured by the latency check; zero until it has run.
    public var inputDelay = Duration.zero

    /// The session's: scale drills take turns through the scales of its mode, in its position. Nil in free practice.
    public var theme: Theme?

    /// Scales and triads only: the fade stages reached before the run.
    public var fadeStages = FadeStages()

    public var seed: UInt64

    public init(fretboard: Fretboard, options: DrillOptions = .init(), key: Key? = nil,
                weighting: NoteWeighting? = nil, seed: UInt64) {
        self.fretboard = fretboard
        self.options = options
        self.key = key
        self.weighting = weighting
        self.seed = seed
    }

    /// What drills built on a key use: the setup's, or the options' where it has none.
    var chosenKey: Key { key ?? options.key }

    /// With that key for its own.
    func spelledInChosenKey() -> DrillSetup {
        var setup = self
        setup.key = chosenKey
        return setup
    }

    /// Every location in range: included strings, fret range, at or above the capo.
    public var locationsInRange: [FretboardLocation] {
        fretboard.strings
            .filter { options.strings?.contains($0) ?? true }
            .flatMap { fretboard.locations(onString: $0, frets: options.frets) }
    }

    /// The locations in range that pass the Notes filter.
    public var candidateLocations: [FretboardLocation] {
        locationsInRange.filter { options.notes == .all || fretboard.pitch(at: $0).pitchClass.isNatural }
    }

    /// A prompt for a note on a string, spelled in the key.
    public func prompt(_ pitchClass: PitchClass, onString string: Int) -> NotePrompt {
        NotePrompt(name: Key.spell(pitchClass, in: key), string: string)
    }

    /// A prompt for one location, spelled in the key.
    public func prompt(at location: FretboardLocation, sweep: Int? = nil) -> NotePrompt {
        NotePrompt(name: fretboard.name(at: location, in: key), string: location.string, target: location, sweep: sweep)
    }

    /// Why no location can be prompted, for next to a disabled Start; nil when some can.
    public var nothingToPromptReason: String? {
        if !candidateLocations.isEmpty { return nil }
        return locationsInRange.isEmpty ? Self.noFretsReason : Self.noNaturalsReason
    }

    static let noFretsReason = "The capo leaves no frets to play in this range."
    static let noNaturalsReason = "No natural notes in these frets and strings. Choose All notes."
}

extension DrillSetup {
    /// Progressions only: the chosen position of the key's scale, or with a theme, the theme's. Nil when it isn't on
    /// the neck.
    public var progressionPosition: Position? {
        if let theme { return theme.position(on: fretboard) }
        let id = options.position
        let positions = fretboard.positions(of: chosenKey.scale, system: options.positionSystem)
        return positions.first { $0.id == id }
            ?? positions.first { $0.system == id.system && $0.number == id.number && $0.octave == 0 }
            ?? positions.first { $0.number == 1 && $0.octave == 0 }
    }

    /// Progressions only: why a run would have nothing to ask; nil when every chord has a voicing in the position.
    public var progressionProblem: String? {
        guard let progression = options.progression else { return "Choose a progression." }
        let key = chosenKey
        guard progression.mode == key.mode else { return "\(progression.name) isn’t in \(key)." }
        guard let position = progressionPosition else { return "The position doesn’t fit the neck." }
        let missing = Set(progression.chords(in: key)).filter { fretboard.voicings(of: $0, in: position).isEmpty }
        guard !missing.isEmpty else { return nil }
        let names = progression.chords(in: key).filter(missing.contains).map(\.shortName).uniqued()
        return "\(names.joined(separator: ", ")) \(names.count == 1 ? "has" : "have") no voicing in the "
            + "\(position.name): choose another position."
    }
}

extension Array where Element: Hashable {
    /// Without repeats, in order.
    fileprivate func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
