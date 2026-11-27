import TheoryCore

extension DrillKind {
    public static let triadPlayIt = DrillKind(
        id: "triadPlayIt", module: .triads, title: "Triad → play it",
        instructions: "Arpeggiate the triad on the strings shown, low to high.",
        symbol: "triangle", traits: [.hidesNote, .offersInversions],
        rules: TriadPlayItRules.self)
}

extension TriadFacts {
    /// "A minor · 1st inversion".
    public var text: String { "\(triad.name) · \(inversion.name)" }
}

/// Triad → play it: a chord, an inversion and a string set, arpeggiated low to high. The first note picks one of the
/// voicings in range and the others must belong to it. The engine sees one prompt, and records one attempt, per note;
/// the notes of a voicing share a group.
public struct TriadPlayItRules: DrillRules {
    public static var kind: DrillKind { .triadPlayIt }

    /// With the key the chords are from.
    public let setup: DrillSetup
    private let choices: [TriadFacts]
    private var chooser: PromptChooser

    private var asked: TriadFacts?
    private var group = -1
    /// Which note of the voicing is up (0 = lowest).
    private var noteIndex = 0
    private var voicing: TriadVoicing?
    private var hasNextNote = false
    private var fade: VoicingFade

    public init(setup: DrillSetup) {
        let setup = setup.spelledInChosenKey()
        self.setup = setup
        choices = setup.triadsInRange
        chooser = PromptChooser(setup: setup)
        fade = VoicingFade(setup: setup)
    }

    public var nothingToPromptReason: String? {
        choices.isEmpty ? "No voicing of the key’s chords fits these frets, string sets and inversions." : nil
    }

    public mutating func begin() {
        hasNextNote = false
    }

    public mutating func nextPrompt(after previous: NotePrompt?) -> NotePrompt? {
        if hasNextNote {
            hasNextNote = false
            noteIndex += 1
        } else {
            guard let next = chooser.choose(from: choices, avoiding: asked, note: \.triad.root.pitchClass) else { return nil }
            asked = next
            group += 1
            noteIndex = 0
            voicing = nil
            fade.start(next)
        }
        return asked.map {
            NotePrompt(name: $0.triad.tones(in: $0.inversion)[noteIndex], string: $0.stringSet.string(ofNote: noteIndex),
                       target: voicing?.locations[noteIndex])
        }
    }

    public func judge(_ answer: DrillAnswer, for prompt: NotePrompt) -> DrillJudgement {
        guard case .played(let pitch) = answer else { return .ignored }
        let location = possibleVoicings.map { $0.locations[noteIndex] }.first { setup.fretboard.pitch(at: $0) == pitch }
        return location.map { .right($0) } ?? .wrong(.pitch(pitch))
    }

    public mutating func dealtWith(_ attempt: Attempt) {
        fade.dealtWith(attempt)
        guard let location = attempt.location else { return }
        voicing = possibleVoicings.first { $0.locations[noteIndex] == location }
        hasNextNote = !isLastNote
    }

    /// The voicing picked, or all in range.
    private var possibleVoicings: [TriadVoicing] {
        if let voicing { [voicing] } else { asked.map(setup.voicingsInRange) ?? [] }
    }

    private var isLastNote: Bool { noteIndex == (asked?.noteCount ?? 0) - 1 }

    /// The voicing picked, or the lowest in range.
    private var revealed: TriadVoicing? { possibleVoicings.first }

    public var isPartWay: Bool { noteIndex > 0 }

    public var isTimed: Bool { fade.isTimed }

    public mutating func hint(isShown: Bool) { fade.hint(isShown: isShown) }

    public var fadeLevels: FadeLevels? {
        get { fade.reached }
        set { if let newValue { fade.reached = newValue } }
    }

    public func correctLocations(for prompt: NotePrompt) -> [FretboardLocation] { revealed?.locations ?? [] }

    public func group(for prompt: NotePrompt) -> AttemptGroup? {
        AttemptGroup(number: group, size: asked?.noteCount, place: noteIndex)
    }

    public func facts(for prompt: NotePrompt) -> AttemptFacts? { asked.map { .triad(fade.logged($0)) } }

    public func transition(after attempt: Attempt) -> DrillTransition {
        attempt.outcome == .answered && !isLastNote ? .continuous : .standard(after: attempt)
    }

    public func display(of moment: DrillMoment) -> DrillDisplay {
        guard let asked else { return DrillDisplay(standard: moment, in: setup) }
        let played = moment.attempts.filter { $0.group?.number == group && $0.outcome == .answered }
        return DrillDisplay(triad: asked, at: revealed?.locations ?? [], played: played, showing: fade.shown, moment: moment, in: setup)
    }
}

extension DrillDisplay {
    /// A voicing being arpeggiated, with the notes played so far; of the rest, what the fade stage shows until it is over.
    init(triad facts: TriadFacts, at locations: [FretboardLocation], played: [Attempt], showing stage: FadeStage,
         moment: DrillMoment, in setup: DrillSetup) {
        self.init(standard: moment, in: setup)
        let isOver = result == .timedOut || played.count == facts.noteCount
        let tones = facts.triad.tones(in: facts.inversion)
        let tuning = setup.fretboard.tuning

        headline = facts.text
        subline = facts.stringSet.name
        highlightedStrings = Set(facts.stringSet.strings)
        // Until it is over, when Hidden, the earlier notes would give the voicing away.
        markers = locations.enumerated().compactMap { index, location in
            let isLast = index == played.count - 1, isNamed = isOver || isLast || stage == .shown
            guard isNamed || stage == .faded else { return nil }
            return Marker(location: location, label: isNamed ? tones[index].description : "",
                          isAnswer: tones[index] == facts.triad.root, isFaint: !isNamed, isLastPlayed: isLast)
        }
        chips = facts.stringSet.strings.enumerated().map { index, string in
            let state: Chip.State = if index < played.count { .found } else if isOver { .timedOut }
                else { index == played.count ? .current : .waiting }
            let isNamed = index < played.count || isOver || stage == .shown
            return Chip(title: "\(tuning.stringNumber(ofString: string))", spokenTitle: tuning.stringLabel(ofString: string),
                        text: isNamed ? tones[index].description : "?", state: state)
        }
        if result == .wrong, moment.wrongAnswers.last?.pitchClass == moment.prompt.pitchClass {
            feedback += ", in another octave"
        } else if result == .right {
            feedback = "\(secondsText(played.compactMap(\.responseTime).reduce(.zero, +), decimals: 2)) s"
        }
    }
}

extension TriadFacts {
    var noteCount: Int { triad.notes.count }
}

extension DrillSetup {
    /// The voicings of a prompt in the fret range, ordered up the neck.
    func voicingsInRange(of facts: TriadFacts) -> [TriadVoicing] {
        fretboard.voicings(of: facts.triad, inversion: facts.inversion, on: facts.stringSet, frets: options.frets)
    }

    /// Every chord of the key in every included inversion and string set that has a voicing in range.
    var triadsInRange: [TriadFacts] {
        let sets = fretboard.stringSets.filter(options.stringSets.contains)
        let inversions = Triad.Inversion.allCases.filter(options.inversions.contains)
        return chosenKey.chords.flatMap { triad in
            sets.flatMap { set in inversions.map { TriadFacts(triad: triad, inversion: $0, stringSet: set) } }
        }
        .filter { !voicingsInRange(of: $0).isEmpty }
    }
}
