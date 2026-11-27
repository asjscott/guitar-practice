import TheoryCore

/// Which of a run's groups an attempt is in: the attempts of one sweep, pass, triad prompt or climb.
public struct AttemptGroup: Hashable, Sendable {
    /// Tells the run's groups apart.
    public let number: Int

    /// How many attempts the whole group has, and which this is (0 = first); nil in All instances' sweeps. With them
    /// the log shows whether a group is complete.
    public let size: Int?
    public let place: Int?

    /// Which of the run's circles of fifths the group is in (`CircleResult`); nil outside one. The log gives each
    /// circle an id.
    public let circle: Int?

    public init(number: Int, size: Int? = nil, place: Int? = nil, circle: Int? = nil) {
        self.number = number
        self.size = size
        self.place = place
        self.circle = circle
    }
}

/// What the log keeps about an attempt beyond its prompt and outcome (ADR 0003).
public enum AttemptFacts: Hashable, Sendable {
    case pass(PassFacts)
    case triad(TriadFacts)
    case chord(ChordFacts)
}

/// The pass a note was in, and how it was played.
public struct PassFacts: Hashable, Sendable {
    public var scale: Scale
    public var position: Position.ID
    public var startDegree: Scale.Degree

    /// BPM, counting clicks.
    public var tempo: Int

    public var signature: TimeSignature

    /// What the pass was played at.
    public var fadeLevel: FadeLevel

    /// Whether a hint had been used in the pass by the time this note was dealt with.
    public var hinted: Bool

    /// The onset, input delay taken off, less the time the nearest click was heard: positive = late. Nil unless
    /// answered.
    public var clickOffset: Duration?

    /// What was taken off the onsets.
    public var inputDelay: Duration

    public init(scale: Scale, position: Position.ID, startDegree: Scale.Degree, tempo: Int, signature: TimeSignature,
                fadeLevel: FadeLevel, hinted: Bool, clickOffset: Duration?, inputDelay: Duration = .zero) {
        self.scale = scale
        self.position = position
        self.startDegree = startDegree
        self.tempo = tempo
        self.signature = signature
        self.fadeLevel = fadeLevel
        self.hinted = hinted
        self.clickOffset = clickOffset
        self.inputDelay = inputDelay
    }
}

/// The triad a note was asked for in.
public struct TriadFacts: Hashable, Sendable {
    public var triad: Triad
    public var inversion: Triad.Inversion
    public var stringSet: StringSet

    /// What the voicing was played at; nil where it isn't being played.
    public var fadeLevel: FadeLevel?

    /// Whether a hint had been used in the voicing by the time this note was dealt with.
    public var hinted = false

    public init(triad: Triad, inversion: Triad.Inversion, stringSet: StringSet) {
        self.triad = triad
        self.inversion = inversion
        self.stringSet = stringSet
    }
}

/// How a chord of a time through went. The raw values are saved in the attempt log: never change them.
public enum ChordOutcome: String, Hashable, Sendable, CaseIterable {
    /// An accepted voicing, low to high, with no wrong note before it and no hint.
    case clean
    /// A wrong pitch, another voicing, or a hint.
    case wrong
    /// Not all three notes in the chord's window, and no wrong one.
    case missed
}

/// A chord of a time through, as it was asked for and played: one attempt per chord.
public struct ChordFacts: Hashable, Sendable {
    public var progression: Progression
    public var key: Key
    /// Which chord of the progression, from 0.
    public var place: Int
    public var triad: Triad
    public var position: Position.ID
    /// Nil if no voicing of the chord was played.
    public var played: TriadVoicing?
    /// Every voicing that would have been clean.
    public var accepted: [TriadVoicing]
    public var style: BackingStyle
    /// BPM.
    public var tempo: Int
    /// What the chord's voicing was played at.
    public var fadeLevel: FadeLevel
    /// Whether H was held during the chord.
    public var hinted: Bool
    public var outcome: ChordOutcome
    /// The first note's onset, input delay taken off, less the chord's first beat: negative = early. Nil if nothing
    /// was played in its window.
    public var firstOnset: Duration?
    /// What was taken off the onsets.
    public var inputDelay: Duration

    /// The chord's numeral, as the progression writes it.
    public var numeral: Progression.Numeral { progression.steps[place].numeral }

    public init(progression: Progression, key: Key, place: Int, triad: Triad, position: Position.ID,
                played: TriadVoicing?, accepted: [TriadVoicing], style: BackingStyle, tempo: Int,
                fadeLevel: FadeLevel, hinted: Bool, outcome: ChordOutcome, firstOnset: Duration?,
                inputDelay: Duration) {
        self.progression = progression
        self.key = key
        self.place = place
        self.triad = triad
        self.position = position
        self.played = played
        self.accepted = accepted
        self.style = style
        self.tempo = tempo
        self.fadeLevel = fadeLevel
        self.hinted = hinted
        self.outcome = outcome
        self.firstOnset = firstOnset
        self.inputDelay = inputDelay
    }
}

extension Attempt {
    /// A chord's facts, in a progression drill.
    public var chord: ChordFacts? {
        if case .chord(let facts) = facts { facts } else { nil }
    }
}

/// How much of a position or a triad's voicing was shown while it was played, before fade levels. The log keeps it,
/// read as a level (`FadeLevel.init(_:)`). The raw values are saved in the attempt log: never change them.
public enum FadeStage: String, Hashable, Sendable, CaseIterable {
    case shown, faded, hidden
}
