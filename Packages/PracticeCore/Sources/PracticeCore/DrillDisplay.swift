import TheoryCore

/// The state a drill's rules turn into a display.
public struct DrillMoment: Hashable, Sendable {
    public let prompt: NotePrompt

    /// Never idle or paused.
    public let phase: DrillPhase

    /// Waiting, but not listening yet.
    public let isHeld: Bool

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

    /// A dot on the neck. The answer, or in a triad the root, has its own colour.
    public struct Marker: Hashable, Sendable {
        public var location: FretboardLocation
        /// Empty when faint.
        public var label: String
        public var isAnswer: Bool
        /// Drawn faintly.
        public var isFaint: Bool
        /// From 1 (solid) down to 0 as it fades by time (`NoteFade`), label and all; never 0.
        public var opacity: Double
        /// Ringed as the last note played.
        public var isLastPlayed: Bool

        public init(location: FretboardLocation, label: String, isAnswer: Bool, isFaint: Bool = false, opacity: Double = 1,
                    isLastPlayed: Bool = false) {
            self.location = location
            self.label = label
            self.isAnswer = isAnswer
            self.isFaint = isFaint
            self.opacity = opacity
            self.isLastPlayed = isLastPlayed
        }
    }

    /// One part of a prompt with several, such as a location of a sweep ("6" over "fret 8"), a string of a triad or
    /// a voicing of a climb.
    public struct Chip: Hashable, Sendable {
        public enum State: Hashable, Sendable {
            case waiting, current, found, timedOut, skipped
        }

        public var title: String
        /// The title in full: "string 6 (E)".
        public var spokenTitle: String
        public var text: String
        public var state: State

        public init(title: String, spokenTitle: String, text: String, state: State) {
            self.title = title
            self.spokenTitle = spokenTitle
            self.text = text
            self.state = state
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

    /// Strings lit along their length (internal indices).
    public var highlightedStrings: Set<Int>

    public var markers: [Marker]

    /// A row under the feedback; empty in most drills.
    public var chips: [Chip] = []

    /// A climb's voicings, up and back; empty in other drills.
    public var voicings: [Chip] = []

    /// The pass, in scale drills.
    public var pass: PassProgress?

    /// The time through, in progression drills.
    public var progression: ProgressionProgress?

    /// Waiting for a typed name: what is typed so far replaces the headline.
    public var acceptsTypedName = false

    init(headline: String, subline: String, feedback: String, result: Result, markers: [Marker]) {
        self.headline = headline
        self.subline = subline
        self.feedback = feedback
        self.result = result
        self.markers = markers
        highlightedStrings = []
    }

    /// The display most drills start from, and change what differs.
    public init(standard moment: DrillMoment, in setup: DrillSetup) {
        let prompt = moment.prompt
        headline = prompt.noteName
        subline = "on \(prompt.stringLabel(in: setup.fretboard.tuning))"
        highlightedStrings = [prompt.string]
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
            feedback = moment.isHeld ? "Wait for the chime" : "Listening…"
        }
    }
}
