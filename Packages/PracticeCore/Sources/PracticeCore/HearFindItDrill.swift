import TheoryCore

extension DrillKind {
    public static let hearFindIt = DrillKind(
        id: "hearFindIt", title: "Hear → find it", instructions: "Hear the open string, then a note. Find that note.",
        symbol: "ear", needsSound: true, hidesNote: true, repeatTitle: "Replay", rules: HearFindItRules.self)
}

/// Hear → find it: the open string sounds, then a target 1–12 frets above it. Only the exact pitch is right, and the
/// note stays hidden until the prompt ends. The timer runs from the target sounding.
public struct HearFindItRules: DrillRules {
    public static var kind: DrillKind { .hearFindIt }
    public static let timeout: Duration = .seconds(15)

    private static let toneDuration: Duration = .milliseconds(600)
    private static let targetRange = Interval(1)...Interval(12)

    public let setup: DrillSetup
    private var chooser: PromptChooser

    public init(setup: DrillSetup) {
        self.setup = setup
        chooser = PromptChooser(setup: setup)
    }

    private func isTarget(_ location: FretboardLocation) -> Bool {
        setup.fretboard.locations(onString: location.string, frets: setup.options.frets, aboveOpen: Self.targetRange)
            .contains(location)
    }

    public var nothingToPromptReason: String? {
        if setup.candidateLocations.contains(where: isTarget) { return nil }
        return setup.locationsInRange.contains(where: isTarget) ? DrillSetup.noNaturalsReason : DrillSetup.noFretsReason
    }

    public mutating func nextPrompt(after previous: NotePrompt?) -> NotePrompt? {
        let prompts = setup.candidateLocations.filter(isTarget).map { setup.prompt(at: $0) }
        return chooser.choose(from: prompts, avoiding: previous)
    }

    public func judge(_ answer: DrillAnswer, for prompt: NotePrompt) -> DrillJudgement {
        guard case .played(let pitch) = answer, let target = prompt.target else { return .ignored }
        return pitch == setup.fretboard.pitch(at: target) ? .right(target) : .wrong(.pitch(pitch))
    }

    public func correctLocations(for prompt: NotePrompt) -> [FretboardLocation] {
        prompt.target.map { [$0] } ?? []
    }

    public func sounds(for prompt: NotePrompt) -> [DrillTone] {
        guard let target = prompt.target else { return [] }
        return [setup.fretboard.soundingOpenPitch(ofString: prompt.string), setup.fretboard.pitch(at: target)]
            .map { DrillTone(pitch: $0, duration: Self.toneDuration) }
    }

    public func timerDelay(for prompt: NotePrompt) -> Duration { Self.toneDuration }

    public mutating func repeated() -> DrillRepeat { .replaySounds }

    public func display(of moment: DrillMoment) -> DrillDisplay {
        var display = DrillDisplay(standard: moment, in: setup)
        guard let target = moment.prompt.target else { return display }
        switch moment.phase {
        case .correct, .timedOut:
            display.subline += " · fret \(target.fret)"
        case .wrong:
            display.headline = "♪"
            if case .pitch(let played) = moment.wrongAnswers.last {
                display.feedback = played < setup.fretboard.pitch(at: target) ? "Too low" : "Too high"
            }
        case .waiting, .idle, .paused:
            display.headline = "♪"
        }
        return display
    }
}
