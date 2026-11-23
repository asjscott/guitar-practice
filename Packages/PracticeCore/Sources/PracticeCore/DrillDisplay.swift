import TheoryCore

/// The state a drill's rules turn into a display.
public struct DrillMoment: Hashable, Sendable {
    public let prompt: NotePrompt

    /// Never idle or paused.
    public let phase: DrillPhase

    /// Wrong answers to this prompt so far.
    public let wrongAnswers: [WrongAnswer]

    /// The run's attempts, including this prompt's once it is answered or timed out.
    public let attempts: [Attempt]

    /// The locations that answer the prompt.
    public let correctLocations: [FretboardLocation]
}

/// What the target card and the neck show for a prompt, worked out here so it can be tested.
public struct DrillDisplay: Hashable, Sendable {
    public enum Result: Hashable, Sendable {
        case waiting, wrong, right, timedOut
    }

    /// A dot on the neck. The answer has its own colour.
    public struct Marker: Hashable, Sendable {
        public var location: FretboardLocation
        public var label: String
        public var isAnswer: Bool

        public init(location: FretboardLocation, label: String, isAnswer: Bool) {
            self.location = location
            self.label = label
            self.isAnswer = isAnswer
        }
    }

    /// The card's big line: "F♯".
    public var headline: String

    /// The line under it: "on string 3 (G)".
    public var subline: String

    /// "You played G", "Fret 7 · 0.82 s", "Listening…".
    public var feedback: String

    /// Tints the card.
    public var result: Result

    /// A string lit along its length (internal index); nil = none.
    public var highlightedString: Int?

    public var markers: [Marker]

    /// The display most drills start from, and change what differs.
    public init(standard moment: DrillMoment, in setup: DrillSetup) {
        let prompt = moment.prompt
        headline = prompt.noteName
        subline = "on \(prompt.stringLabel(in: setup.fretboard.tuning))"
        highlightedString = prompt.string
        markers = []
        switch moment.phase {
        case .wrong(let played):
            result = .wrong
            feedback = "You played \(Key.spell(played, in: setup.key))"
        case .correct(let location):
            result = .right
            feedback = moment.attempts.last?.rightAnswerText ?? ""
            markers = [Marker(location: location, label: prompt.noteName, isAnswer: true)]
        case .timedOut:
            result = .timedOut
            feedback = "Time's up — here it is"
            markers = moment.correctLocations.map { Marker(location: $0, label: prompt.noteName, isAnswer: false) }
        case .waiting, .idle, .paused:
            result = .waiting
            feedback = "Listening…"
        }
    }
}
