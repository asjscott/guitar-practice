import TheoryCore

extension DrillKind {
    public static let fretNameIt = DrillKind(
        id: "fretNameIt", module: .notes, title: "Fret → name it", instructions: "A fret lights up. Type its name, then Return.",
        symbol: "keyboard", traits: [.usesKeyboard, .hidesNote], rules: FretNameItRules.self)
}

/// Fret → name it: a fretboard location lights up, and any enharmonic name for its note, typed, is right.
public struct FretNameItRules: DrillRules {
    public static var kind: DrillKind { .fretNameIt }

    public let setup: DrillSetup
    private var chooser: PromptChooser

    public init(setup: DrillSetup) {
        self.setup = setup
        chooser = PromptChooser(setup: setup)
    }

    public mutating func nextPrompt(after previous: NotePrompt?) -> NotePrompt? {
        chooser.choose(from: setup.candidateLocations.map { setup.prompt(at: $0) }, avoiding: previous)
    }

    public func judge(_ answer: DrillAnswer, for prompt: NotePrompt) -> DrillJudgement {
        guard case .named(let name) = answer, let target = prompt.target else { return .ignored }
        return name.pitchClass == prompt.pitchClass ? .right(target) : .wrong(.name(name))
    }

    public func correctLocations(for prompt: NotePrompt) -> [FretboardLocation] {
        prompt.target.map { [$0] } ?? []
    }

    public func display(of moment: DrillMoment) -> DrillDisplay {
        var display = DrillDisplay(standard: moment, in: setup)
        let prompt = moment.prompt
        guard let target = prompt.target else { return display }
        display.subline = "\(prompt.stringLabel(in: setup.fretboard.tuning)) · fret \(target.fret)"
        switch moment.phase {
        case .correct:
            let time = moment.attempts.last?.responseTime.map { " · \(secondsText($0, decimals: 2)) s" } ?? ""
            display.feedback = prompt.noteName + time
        case .timedOut:
            display.feedback = "Time's up — it's \(prompt.noteName)"
        case .waiting, .wrong, .idle, .paused:
            display.headline = "?"
            display.acceptsTypedName = true
            display.markers = [.init(location: target, label: "?", isAnswer: false)]
            display.feedback = moment.wrongAnswers.last.map { "Not \($0.text())" } ?? "Type its name, then Return"
        }
        return display
    }
}
