import TheoryCore

public typealias NotePlayItDrill = PromptDrill<NotePlayItRules>
public typealias NotePlayItOptions = DrillOptions

extension DrillKind {
    public static let notePlayIt = DrillKind(
        id: "notePlayIt", module: .notes, title: "Note → play it", instructions: "Play the note on the string shown.",
        symbol: "target", offersOrder: true, rules: NotePlayItRules.self)
}

/// Note → play it: a note and a string; any fret on the string that gives the note is right.
/// It asks TheoryCore which fretboard locations answer a prompt; it does no note maths.
public struct NotePlayItRules: DrillRules {
    public static var kind: DrillKind { .notePlayIt }

    public let setup: DrillSetup
    private var chooser: PromptChooser
    private var queue: [NotePrompt] = []

    public init(setup: DrillSetup) {
        self.setup = setup
        chooser = PromptChooser(setup: setup)
    }

    private var isCheck: Bool { setup.options.order == .inOrder }

    /// A check ignores the Notes filter: it walks every location in range.
    public var nothingToPromptReason: String? {
        isCheck && !setup.locationsInRange.isEmpty ? nil : setup.nothingToPromptReason
    }

    /// "In order (check)": one prompt per location in range, string 6 first, fret by fret.
    public mutating func begin() {
        queue = isCheck ? setup.locationsInRange.map { setup.prompt(at: $0) } : []
    }

    public mutating func nextPrompt(after previous: NotePrompt?) -> NotePrompt? {
        if isCheck { return queue.isEmpty ? nil : queue.removeFirst() }
        return chooser.choose(from: randomPrompts, avoiding: previous)
    }

    /// Random order: each distinct (note, string) once.
    private var randomPrompts: [NotePrompt] {
        var seen = Set<NotePrompt>()
        return setup.candidateLocations
            .map { setup.prompt(setup.fretboard.pitch(at: $0).pitchClass, onString: $0.string) }
            .filter { seen.insert($0).inserted }
    }

    public func judge(_ answer: DrillAnswer, for prompt: NotePrompt) -> DrillJudgement {
        guard case .played(let pitch) = answer else { return .ignored }
        if pitch.pitchClass == prompt.pitchClass,
           let location = setup.fretboard.location(of: pitch, onString: prompt.string, frets: setup.options.frets) {
            return .right(location)
        }
        return .wrong(.note(pitch.pitchClass))
    }

    public func correctLocations(for prompt: NotePrompt) -> [FretboardLocation] {
        setup.fretboard.locations(of: prompt.pitchClass, onString: prompt.string, frets: setup.options.frets)
    }

    /// A check asks for the same location again, so that none is missed.
    public var resumeRule: DrillResumeRule { isCheck ? .samePrompt(keepingWrongAnswers: false) : .newPrompt }

    public func display(of moment: DrillMoment) -> DrillDisplay {
        var display = DrillDisplay(standard: moment, in: setup)
        if let target = moment.prompt.target { display.subline += " · fret \(target.fret)" }
        return display
    }
}
