import TheoryCore

extension DrillKind {
    public static let inversions = DrillKind(
        id: "inversions", module: .triads, title: "Inversions",
        instructions: "Arpeggiate every voicing of the chord up the string set and back, each low to high.",
        symbol: "stairs", traits: [.hidesNote, .hasClimbs], repeatTitle: "Restart", rules: InversionsRules.self)
}

extension Triad.Inversion {
    /// "root", "1st", "2nd".
    public var shortName: String {
        switch self {
        case .root: "root"
        case .first: "1st"
        case .second: "2nd"
        }
    }
}

/// Inversions: climbs. One chord on one string set, through every voicing in range by fret, up and back, the highest
/// once. The engine sees one prompt, and records one attempt, per note; the notes of a climb share a group. R starts the
/// same climb again, as a new group.
public struct InversionsRules: DrillRules {
    public static var kind: DrillKind { .inversions }

    private struct Climb: Equatable {
        /// As they are asked for, up and back.
        let voicings: [TriadVoicing]

        init(up: [TriadVoicing]) {
            voicings = up + up.dropLast().reversed()
        }

        var triad: Triad { voicings[0].triad }
    }

    private enum Next {
        case climb, voicing, note
        /// The voicing that is up, from its lowest note.
        case sameVoicing
    }

    /// With the key the chords are from.
    public let setup: DrillSetup
    private let choices: [Climb]
    private var chooser: PromptChooser

    private var climb: Climb?
    private var group = -1
    /// Which voicing of the climb is up.
    private var voicingIndex = 0
    /// Its notes played since it last started, lowest first.
    private var played: [Attempt] = []
    /// How the climb's voicings went, so far.
    private var results: [DrillDisplay.Chip.State] = []
    private var next = Next.climb
    private var fade: VoicingFade

    public init(setup: DrillSetup) {
        let setup = setup.spelledInChosenKey()
        self.setup = setup
        choices = setup.climbableVoicings.map { Climb(up: $0) }
        chooser = PromptChooser(setup: setup)
        fade = VoicingFade(setup: setup)
    }

    public var nothingToPromptReason: String? {
        choices.isEmpty ? "No chord of the key has two voicings in these frets and string sets." : nil
    }

    public mutating func begin() {
        next = .climb
    }

    public mutating func nextPrompt(after previous: NotePrompt?) -> NotePrompt? {
        let isNewVoicing = next != .note
        switch next {
        case .climb:
            guard let chosen = chooser.choose(from: choices, avoiding: climb, note: \.triad.root.pitchClass) else { return nil }
            start(chosen)
        case .voicing:
            voicingIndex += 1
            played = []
        case .sameVoicing:
            played = []
        case .note:
            break
        }
        if isNewVoicing, let facts { fade.start(facts) }
        // Unless this prompt is dealt with first: then a pause dropped it.
        next = .sameVoicing
        return voicing.map {
            let target = $0.locations[noteIndex]
            return NotePrompt(name: $0.triad.tones(in: $0.inversion)[noteIndex], string: target.string, target: target)
        }
    }

    private mutating func start(_ climb: Climb) {
        self.climb = climb
        group += 1
        voicingIndex = 0
        played = []
        results = []
    }

    private var voicing: TriadVoicing? { climb?.voicings[voicingIndex] }

    /// Which note of the voicing is up (0 = lowest).
    private var noteIndex: Int { played.count }

    private var facts: TriadFacts? {
        voicing.map { TriadFacts(triad: $0.triad, inversion: $0.inversion, stringSet: $0.stringSet) }
    }

    public func judge(_ answer: DrillAnswer, for prompt: NotePrompt) -> DrillJudgement {
        setup.judgeExactPitch(answer, for: prompt)
    }

    public mutating func dealtWith(_ attempt: Attempt) {
        fade.dealtWith(attempt)
        guard let climb, let voicing else { return }
        switch attempt.outcome {
        case .answered:
            played.append(attempt)
            if played.count < voicing.locations.count {
                next = .note
                return
            }
            results.append(.found)
        case .timedOut:
            results.append(.timedOut)
        case .skipped:
            results.append(.skipped)
        }
        next = voicingIndex + 1 < climb.voicings.count ? .voicing : .climb
    }

    public mutating func repeated() -> DrillRepeat {
        guard let climb else { return .ignored }
        start(climb)
        next = .sameVoicing
        return .newPrompt
    }

    public var isPartWay: Bool { noteIndex > 0 }

    public var isTimed: Bool { fade.isTimed }

    public mutating func hint(isShown: Bool) { fade.hint(isShown: isShown) }

    public var fadeStages: FadeStages? {
        get { fade.reached }
        set { if let newValue { fade.reached = newValue } }
    }

    public func correctLocations(for prompt: NotePrompt) -> [FretboardLocation] { voicing?.locations ?? [] }

    public func group(for prompt: NotePrompt) -> AttemptGroup? {
        guard let climb, let voicing else { return nil }
        let noteCount = voicing.locations.count
        return AttemptGroup(number: group, size: climb.voicings.count * noteCount, place: voicingIndex * noteCount + noteIndex)
    }

    public func facts(for prompt: NotePrompt) -> AttemptFacts? { facts.map { .triad(fade.logged($0)) } }

    /// Straight on within a voicing.
    public func transition(after attempt: Attempt) -> DrillTransition {
        attempt.outcome == .answered && next == .note ? .continuous : .standard(after: attempt)
    }

    public var resumeRule: DrillResumeRule { .samePart }

    public func display(of moment: DrillMoment) -> DrillDisplay {
        guard let climb, let voicing, let facts else { return DrillDisplay(standard: moment, in: setup) }
        var display = DrillDisplay(triad: facts, at: voicing.locations, played: played, showing: fade.shown, moment: moment, in: setup)
        display.voicings = climb.voicings.enumerated().map { index, voicing in
            let state: DrillDisplay.Chip.State = if index < results.count { results[index] } else { index == voicingIndex ? .current : .waiting }
            return DrillDisplay.Chip(title: voicing.inversion.shortName, spokenTitle: "voicing \(index + 1) of \(climb.voicings.count)",
                                     text: voicing.inversion.name, state: state)
        }
        return display
    }
}

extension DrillSetup {
    /// Per chord of the key and included string set, its voicings in range in every inversion, ordered up the neck.
    /// Those with fewer than two are left out.
    fileprivate var climbableVoicings: [[TriadVoicing]] {
        chosenKey.chords.flatMap { triad in
            fretboard.stringSets.filter(options.stringSets.contains).map {
                fretboard.voicings(of: triad, on: $0, frets: options.frets)
            }
        }
        .filter { $0.count >= 2 }
    }
}
