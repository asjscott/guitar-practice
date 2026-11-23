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

    public init() {}
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

    public var seed: UInt64

    public init(fretboard: Fretboard, options: DrillOptions = .init(), key: Key? = nil,
                weighting: NoteWeighting? = nil, seed: UInt64) {
        self.fretboard = fretboard
        self.options = options
        self.key = key
        self.weighting = weighting
        self.seed = seed
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
    public func prompt(at location: FretboardLocation) -> NotePrompt {
        NotePrompt(name: fretboard.name(at: location, in: key), string: location.string, target: location)
    }

    /// Why no location can be prompted, for next to a disabled Start; nil when some can.
    public var nothingToPromptReason: String? {
        if !candidateLocations.isEmpty { return nil }
        if locationsInRange.isEmpty { return "The capo leaves no frets to play in this range." }
        return "No natural notes in these frets and strings. Choose All notes."
    }
}
