import TheoryCore

/// Which of a run's groups an attempt is in: the attempts of one sweep, pass, triad prompt or climb.
public struct AttemptGroup: Hashable, Sendable {
    /// Tells the run's groups apart.
    public let number: Int

    /// How many attempts the whole group has, and which this is (0 = first); nil in sweeps. With them the log shows
    /// whether a group is complete.
    public let size: Int?
    public let place: Int?

    public init(number: Int, size: Int? = nil, place: Int? = nil) {
        self.number = number
        self.size = size
        self.place = place
    }
}

/// What the log keeps about an attempt beyond its prompt and outcome (ADR 0003).
public enum AttemptFacts: Hashable, Sendable {
    case pass(PassFacts)
    case triad(TriadFacts)
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
    public var fadeStage: FadeStage

    /// Whether a hint had been used in the pass by the time this note was dealt with.
    public var hinted: Bool

    /// The onset less the time the nearest click was heard: positive = late. Nil unless answered.
    public var clickOffset: Duration?

    public init(scale: Scale, position: Position.ID, startDegree: Scale.Degree, tempo: Int, signature: TimeSignature,
                fadeStage: FadeStage, hinted: Bool, clickOffset: Duration?) {
        self.scale = scale
        self.position = position
        self.startDegree = startDegree
        self.tempo = tempo
        self.signature = signature
        self.fadeStage = fadeStage
        self.hinted = hinted
        self.clickOffset = clickOffset
    }
}

/// The triad a note was asked for in.
public struct TriadFacts: Hashable, Sendable {
    public var triad: Triad
    public var inversion: Triad.Inversion
    public var stringSet: StringSet

    public init(triad: Triad, inversion: Triad.Inversion, stringSet: StringSet) {
        self.triad = triad
        self.inversion = inversion
        self.stringSet = stringSet
    }
}

/// How much of a position is shown during a pass. The raw values are saved in the attempt log: never change them.
public enum FadeStage: String, Hashable, Sendable, CaseIterable {
    case shown, faded, hidden
}
