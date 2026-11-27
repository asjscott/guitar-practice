import TheoryCore

extension DrillKind {
    public static let triadCircle = DrillKind(
        id: "triadCircle", module: .triads, title: "Triad circle",
        instructions: "Climb each key’s tonic triad up the string set and back, every voicing low to high, round the circle of fifths.",
        symbol: "arrow.triangle.2.circlepath", traits: [.hidesNote, .hasClimbs, .goesRoundTheCircle],
        rules: TriadCircleRules.self)
}

/// Triad circle: twelve climbs, one per key round the circle of fifths from the setup's key, each of the key's tonic
/// triad (major or minor, as the key) on one string set, through every voicing over the setup's frets by fret, up and
/// back, as in Inversions. A voicing expects 10 s and fades at its shape's level (`VoicingFade`); level 0 is shown in
/// full. No note times out; a skip moves on to the next note and leaves the circle not clean. The run ends with the
/// circle.
///
/// The string set is the first of the setup's included sets that holds two voicings of every key's triad (a session's
/// theme gives just one); in some tunings a set with strings an octave apart holds fewer. One attempt per note,
/// grouped by climb (with size and place), all in circle 0. The clock runs on from one voicing and key to the next;
/// a pause keeps the note that is up.
public struct TriadCircleRules: DrillRules {
    public static var kind: DrillKind { .triadCircle }

    /// A triad's.
    private static let noteCount = 3

    public let setup: DrillSetup
    /// The circle, from the setup's key.
    private let keys: [Key]
    /// Each key's climb, up and back; empty where its triad has fewer than two voicings in range.
    private let climbs: [[TriadVoicing]]

    /// Which key's climb is up, which of its voicings, and the voicing's notes dealt with since it started.
    private var place = -1
    private var voicingIndex = 0
    private var played: [Attempt] = []
    /// How the climb's voicings went, so far.
    private var results: [DrillDisplay.Chip.State] = []
    private var fade: VoicingFade

    public init(setup: DrillSetup) {
        self.setup = setup
        let keys = setup.chosenKey.circleOfFifths
        self.keys = keys
        let fretboard = setup.fretboard
        let sets = fretboard.stringSets.filter(setup.options.stringSets.contains)
        let climbsOnEach = sets.map { set in
            keys.map { key -> [TriadVoicing] in
                let up = fretboard.voicings(of: Triad(key.mode == .major ? .major : .minor, root: key.tonic), on: set,
                                            frets: setup.options.frets)
                return up.count < 2 ? [] : up + up.dropLast().reversed()
            }
        }
        climbs = climbsOnEach.first { !$0.contains(where: \.isEmpty) } ?? climbsOnEach.first ?? keys.map { _ in [] }
        fade = VoicingFade(setup: setup)
    }

    public var nothingToPromptReason: String? {
        climbs.contains(where: \.isEmpty) ? "Not every key’s triad has two voicings in these frets on this string set." : nil
    }

    public mutating func begin() {
        place = -1
        voicingIndex = 0
        played = []
        results = []
    }

    public mutating func nextPrompt(after previous: NotePrompt?) -> NotePrompt? {
        let isNewVoicing = place < 0 || played.isEmpty
        if place < 0 {
            guard !climbs.isEmpty, !climbs[0].isEmpty else { return nil }
            place = 0
        }
        guard place < climbs.count, let voicing else { return nil }
        if isNewVoicing, let facts { fade.start(facts) }
        let target = voicing.locations[played.count]
        return NotePrompt(name: voicing.triad.tones(in: voicing.inversion)[played.count], string: target.string,
                          target: target)
    }

    private var climb: [TriadVoicing]? { place >= 0 && place < climbs.count ? climbs[place] : nil }

    private var voicing: TriadVoicing? { climb.flatMap { voicingIndex < $0.count ? $0[voicingIndex] : nil } }

    private var facts: TriadFacts? {
        voicing.map { TriadFacts(triad: $0.triad, inversion: $0.inversion, stringSet: $0.stringSet) }
    }

    /// Whether the circle's last note has been dealt with.
    private var isOver: Bool { place >= climbs.count }

    public func judge(_ answer: DrillAnswer, for prompt: NotePrompt) -> DrillJudgement {
        setup.judgeExactPitch(answer, for: prompt)
    }

    public mutating func dealtWith(_ attempt: Attempt) {
        fade.dealtWith(attempt)
        guard let climb, let voicing else { return }
        played.append(attempt)
        guard played.count == voicing.locations.count else { return }
        results.append(played.contains(where: \.skipped) ? .skipped : .found)
        played = []
        if voicingIndex + 1 < climb.count {
            voicingIndex += 1
        } else {
            place += 1
            voicingIndex = 0
            results = []
        }
    }

    public var resumeRule: DrillResumeRule { .samePrompt(keepingWrongAnswers: true) }

    public var isPartWay: Bool { !played.isEmpty }

    /// Against the best, not a clock.
    public var isTimed: Bool { false }

    public mutating func hint(isShown: Bool) { fade.hint(isShown: isShown) }

    public mutating func timerStarted(at time: Duration) { fade.timerStarted(at: time) }

    public var fadeLevels: FadeLevels? {
        get { fade.reached }
        set { if let newValue { fade.reached = newValue } }
    }

    public func correctLocations(for prompt: NotePrompt) -> [FretboardLocation] { voicing?.locations ?? [] }

    public func group(for prompt: NotePrompt) -> AttemptGroup? {
        guard let climb, let voicing else { return nil }
        let noteCount = voicing.locations.count
        return AttemptGroup(number: place, size: climb.count * noteCount, place: voicingIndex * noteCount + played.count,
                            circle: 0)
    }

    public func facts(for prompt: NotePrompt) -> AttemptFacts? { facts.map { .triad(fade.logged($0)) } }

    /// Straight on within a voicing; into the next voicing or key with the clock running; the circle's end is held
    /// long enough to read its time. `dealtWith` has already moved on.
    public func transition(after attempt: Attempt) -> DrillTransition {
        if isOver { return DrillTransition(pause: DrillTiming.revealPause, timesFromLastPrompt: false) }
        return played.isEmpty ? DrillTransition(pause: DrillTiming.correctPause, timesFromLastPrompt: true) : .continuous
    }

    public func display(of moment: DrillMoment) -> DrillDisplay {
        // Just after a voicing's last note, until the next is up: the voicing as it was played, in its key.
        let shown = moment.phase.isCorrect && played.isEmpty ? lastVoicing(of: moment) : current
        let progress = progress(at: moment, place: shown?.0 ?? place)
        guard let (climbPlace, index, notes) = shown, climbPlace < climbs.count else {
            var display = DrillDisplay(standard: moment, in: setup)
            display.circle = progress
            return display
        }
        let climb = climbs[climbPlace]
        let voicing = climb[index]
        let facts = TriadFacts(triad: voicing.triad, inversion: voicing.inversion, stringSet: voicing.stringSet)
        var display = DrillDisplay(triad: facts, at: voicing.locations, played: notes, fading: fade.noteFade,
                                   moment: moment, in: setup)
        let top = climb.count / 2
        display.subline = "voicing \(index + 1) of \(climb.count) · \(index <= top ? "up" : "down") · \(fade.level)"
        for (note, attempt) in notes.enumerated() where attempt.skipped && note < display.chips.count {
            display.chips[note].state = .skipped
        }
        let states = climbPlace == place ? results : results(ofClimbEndingAt: moment)
        display.voicings = climb.enumerated().map { place, voicing in
            let state: DrillDisplay.Chip.State = if place < states.count { states[place] }
                else { place == index ? .current : .waiting }
            return DrillDisplay.Chip(title: voicing.inversion.shortName, spokenTitle: "voicing \(place + 1) of \(climb.count)",
                                     text: voicing.inversion.name, state: state)
        }
        display.circle = progress
        return display
    }

    /// The climb, voicing and notes that are up.
    private var current: (Int, Int, [Attempt])? { place >= 0 ? (place, voicingIndex, played) : nil }

    /// The voicing whose last note was just played, from the attempts.
    private func lastVoicing(of moment: DrillMoment) -> (Int, Int, [Attempt])? {
        guard let last = moment.attempts.last, let group = last.group, let groupPlace = group.place,
              group.number < climbs.count else { return current }
        let index = groupPlace / Self.noteCount
        let notes = Array(moment.attempts.suffix(Self.noteCount))
        return (group.number, index, notes)
    }

    /// A climb just finished: every voicing as it went.
    private func results(ofClimbEndingAt moment: DrillMoment) -> [DrillDisplay.Chip.State] {
        guard let number = moment.attempts.last?.group?.number else { return [] }
        let attempts = moment.attempts.filter { $0.group?.number == number }
        return stride(from: 0, to: attempts.count, by: Self.noteCount).map {
            attempts[$0..<min($0 + Self.noteCount, attempts.count)].contains(where: \.skipped) ? .skipped : .found
        }
    }

    private func progress(at moment: DrillMoment, place: Int) -> CircleProgress {
        let attempts = moment.attempts
        let isAnswerable = switch moment.phase {
        case .waiting, .wrong: true
        default: false
        }
        let result = CircleResult(attempts: attempts, count: keys.count).flatMap { $0.isComplete ? $0 : nil }
        let runningSince: Duration? = if result != nil {
            nil
        } else if isAnswerable {
            moment.promptStart
        } else if let start = moment.promptStart, let time = attempts.last?.responseTime {
            // Between voicings: from the last right note.
            start + time
        } else {
            nil
        }
        return CircleProgress(
            keys: keys, place: min(max(place, 0), keys.count - 1),
            wrongNotes: attempts.map(\.wrongAnswers.count).reduce(0, +) + (isAnswerable ? moment.wrongAnswers.count : 0),
            skips: attempts.filter(\.skipped).count,
            elapsed: attempts.reduce(.zero) { $0 + ($1.responseTime ?? .zero) },
            runningSince: runningSince, result: result, best: setup.circleBest)
    }
}

private extension DrillPhase {
    var isCorrect: Bool {
        if case .correct = self { true } else { false }
    }
}
