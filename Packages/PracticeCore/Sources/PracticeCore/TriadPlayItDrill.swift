import TheoryCore

extension DrillKind {
    public static let triadPlayIt = DrillKind(
        id: "triadPlayIt", module: .triads, title: "Triad → play it",
        instructions: "Arpeggiate the triad on the strings shown, low to high.",
        symbol: "triangle", hidesNote: true, isInSessions: false, rules: TriadPlayItRules.self)
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
    private var place = 0
    private var voicing: TriadVoicing?
    private var hasNextNote = false

    public init(setup: DrillSetup) {
        var setup = setup
        setup.key = setup.key ?? setup.options.key
        self.setup = setup
        choices = setup.triadsInRange
        chooser = PromptChooser(setup: setup)
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
            place += 1
        } else {
            guard let next = chooser.choose(from: choices, avoiding: asked, note: \.triad.root.pitchClass) else { return nil }
            asked = next
            group += 1
            place = 0
            voicing = nil
        }
        return asked.map {
            NotePrompt(name: $0.triad.tones(in: $0.inversion)[place], string: $0.stringSet.lowestString + place,
                       target: voicing?.locations[place])
        }
    }

    public func judge(_ answer: DrillAnswer, for prompt: NotePrompt) -> DrillJudgement {
        guard case .played(let pitch) = answer else { return .ignored }
        let location = possibleVoicings.map { $0.locations[place] }.first { setup.fretboard.pitch(at: $0) == pitch }
        return location.map { .right($0) } ?? .wrong(.pitch(pitch))
    }

    public mutating func dealtWith(_ attempt: Attempt) {
        guard let location = attempt.location else { return }
        voicing = possibleVoicings.first { $0.locations[place] == location }
        hasNextNote = !isLastNote
    }

    /// The voicing picked, or all in range.
    private var possibleVoicings: [TriadVoicing] {
        if let voicing { [voicing] } else { asked.map(setup.voicingsInRange) ?? [] }
    }

    private var isLastNote: Bool { place == (asked?.noteCount ?? 0) - 1 }

    /// The voicing picked, or the lowest in range.
    private var revealed: TriadVoicing? { possibleVoicings.first }

    public func correctLocations(for prompt: NotePrompt) -> [FretboardLocation] { revealed?.locations ?? [] }

    public func group(for prompt: NotePrompt) -> AttemptGroup? {
        AttemptGroup(number: group, size: asked?.noteCount, place: place)
    }

    public func facts(for prompt: NotePrompt) -> AttemptFacts? { asked.map { .triad($0) } }

    public func transition(after attempt: Attempt) -> DrillTransition {
        attempt.outcome == .answered && !isLastNote ? .continuous : .standard(after: attempt)
    }

    public func display(of moment: DrillMoment) -> DrillDisplay {
        var display = DrillDisplay(standard: moment, in: setup)
        guard let asked else { return display }
        let played = moment.attempts.filter { $0.group?.number == group && $0.outcome == .answered }
        let isOver = display.result == .timedOut || played.count == asked.noteCount
        let tones = asked.triad.tones(in: asked.inversion)
        let tuning = setup.fretboard.tuning

        display.headline = asked.text
        display.subline = asked.stringSet.name
        display.highlightedStrings = Set(asked.stringSet.strings)
        // Until it is over, the earlier notes would give the voicing away.
        display.markers = (revealed?.locations ?? []).enumerated().compactMap { index, location in
            guard isOver || index == played.count - 1 else { return nil }
            return DrillDisplay.Marker(location: location, label: tones[index].description, isAnswer: tones[index] == asked.triad.root,
                                       isLastPlayed: index == played.count - 1)
        }
        display.chips = asked.stringSet.strings.enumerated().map { index, string in
            let state: DrillDisplay.Chip.State = if index < played.count { .found } else if isOver { .timedOut }
                else { index == place ? .current : .waiting }
            let isNamed = index < played.count || isOver
            return DrillDisplay.Chip(title: "\(tuning.stringNumber(ofString: string))", spokenTitle: tuning.stringLabel(ofString: string),
                                     text: isNamed ? tones[index].description : "?", state: state)
        }
        if display.result == .wrong, moment.wrongAnswers.last?.pitchClass == moment.prompt.pitchClass {
            display.feedback += ", in another octave"
        } else if display.result == .right {
            display.feedback = "\(secondsText(played.compactMap(\.responseTime).reduce(.zero, +), decimals: 2)) s"
        }
        return display
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
        return (key ?? options.key).chords.flatMap { triad in
            sets.flatMap { set in inversions.map { TriadFacts(triad: triad, inversion: $0, stringSet: set) } }
        }
        .filter { !voicingsInRange(of: $0).isEmpty }
    }
}
