import TheoryCore

extension DrillKind {
    public static let freeTime = DrillKind(
        id: "freeTime", module: .progressions, title: "Free time",
        instructions: "The backing loops with the position shown: play what you like.",
        symbol: "music.note.house", traits: [.hasBacking, .needsSound, .hasNoPrompts], repeatTitle: nil) {
            FreeTimeDrill(setup: $0)
        }
}

/// Free time: the progression's backing round and round, with the position shown, until it is stopped. There are no
/// prompts and no attempts, and it doesn't fade. Pausing stops the backing; Resume counts it in again.
public struct FreeTimeDrill: Drill {
    public private(set) var phase: DrillPhase = .idle
    public let setup: DrillSetup
    public var attempts: [Attempt] { [] }

    private let key: Key
    private let progression: Progression?
    private let position: Position?
    private let chords: [Triad]
    private var backing: Backing?
    private var pendingBacking: [BackingRequest] = []
    private var now: Duration = .zero

    public init(setup: DrillSetup) {
        self.setup = setup
        key = setup.chosenKey
        progression = setup.options.progression
        position = setup.progressionPosition
        chords = progression?.chords(in: key) ?? []
    }

    public var kind: DrillKind { .freeTime }
    public var prompt: NotePrompt? { nil }
    public var promptStart: Duration? { nil }
    public var timeLimit: Duration { .zero }
    public func timeRemaining(at now: Duration) -> Duration? { nil }
    public var resumesSamePrompt: Bool { false }
    public var canHold: Bool { false }

    public var nothingToPromptReason: String? {
        guard let progression else { return "Choose a progression." }
        guard progression.mode == key.mode else { return "\(progression.name) isn’t in \(key)." }
        return position == nil ? "The position doesn’t fit the neck." : nil
    }

    public mutating func takeSounds() -> [DrillSoundRequest] { [] }

    public mutating func takeBacking() -> [BackingRequest] {
        defer { pendingBacking = [] }
        return pendingBacking
    }

    public mutating func handle(_ event: DrillEvent) {
        switch event {
        case .start(let now):
            guard !isRunning, nothingToPromptReason == nil else { return }
            begin(at: now)
        case .resume(let now):
            guard phase == .paused else { return }
            begin(at: now)
        case .pause(let now):
            self.now = max(self.now, now)
            guard isRunning, phase != .paused else { return }
            phase = .paused
            pendingBacking = [.stop]
        case .stop:
            guard isRunning else { return }
            phase = .idle
            pendingBacking = [.stop]
        case .backingStarted(let heard):
            backing = heard
        case .tick(let now), .played(_, _, let now), .skip(let now), .repeat(let now), .hint(_, let now):
            self.now = max(self.now, now)
        case .typed, .soundStarted, .hold, .clicksStarted, .passSettings, .fadeLevels:
            break
        }
    }

    private mutating func begin(at now: Duration) {
        guard let progression else { return }
        self.now = max(self.now, now)
        let backing = Backing(chords: zip(chords, progression.steps).map { BackingChord($0, bars: $1.bars) },
                              style: setup.options.backing.style, bpm: setup.options.backing.tempo, start: self.now)
        self.backing = backing
        pendingBacking = [.start(backing)]
        phase = .waiting
    }

    /// The chord sounding now; nil during the count-in.
    private var sounding: Triad? {
        guard let backing, let progression, now >= backing.start(ofTimeThrough: 0) else { return nil }
        let length = backing.start(ofTimeThrough: 1) - backing.start(ofTimeThrough: 0)
        let into = (now - backing.start(ofTimeThrough: 0)) / length
        let bar = Int((into - into.rounded(.down)) * Double(backing.barsPerTimeThrough))
        var bars = 0
        for (chord, step) in zip(chords, progression.steps) {
            bars += step.bars
            if bar < bars { return chord }
        }
        return chords.last
    }

    /// The chord that sounds, over the position, its notes named and its roots marked.
    public var display: DrillDisplay? {
        guard isRunning, phase != .paused, let progression, let position else { return nil }
        let scale = position.scale
        let markers = position.locations.map { location in
            let name = fretboard.name(at: location, in: scale)
            return DrillDisplay.Marker(location: location, label: name.description, isAnswer: name == scale.tonic)
        }
        return DrillDisplay(headline: sounding?.shortName ?? "Free time",
                            subline: "\(progression.name) in \(key.shortName) · \(position.name)",
                            feedback: sounding == nil ? "Counting in…" : "Play what you like", result: .waiting,
                            markers: markers)
    }
}
