import TheoryCore

/// How much of a triad's voicing is shown while it is played, and what that comes to: the part of the triad drills that
/// fades. Shown has its dots and names, Faded faint dots, Hidden nothing.
struct VoicingFade: Sendable {
    /// This run's voicings included.
    var reached: FadeStages

    private let override: FadeStage?
    private let tuning: Tuning
    /// What the voicing that is up is played at.
    private var stage = FadeStage.shown
    private var isHinted = false
    /// H is held.
    private var isHintShown = false
    /// The voicing's, since it last started.
    private var notes: [FadeStages.VoicingNote] = []

    init(setup: DrillSetup) {
        reached = setup.fadeStages
        override = setup.options.triadFade
        tuning = setup.fretboard.tuning
    }

    /// Shown can be taken as slowly as it needs to be learned.
    var isTimed: Bool { stage != .shown }

    /// What is shown now.
    var shown: FadeStage { isHintShown ? .shown : stage }

    /// A voicing is up, from its lowest note.
    mutating func start(_ facts: TriadFacts) {
        stage = override ?? reached.stage(of: FadeStages.VoicingShape(facts, in: tuning))
        isHinted = isHintShown
        notes = []
    }

    mutating func hint(isShown: Bool) {
        isHintShown = isShown
        if isShown { isHinted = true }
    }

    /// As they are logged.
    func logged(_ facts: TriadFacts) -> TriadFacts {
        var facts = facts
        facts.fadeStage = stage
        facts.hinted = isHinted
        return facts
    }

    /// Counts a note that was dealt with; the voicing's last counts the voicing.
    mutating func dealtWith(_ attempt: Attempt) {
        guard let note = FadeStages.VoicingNote(attempt, in: tuning) else { return }
        notes.append(note)
        // Nothing is counted until the voicing is over.
        reached.add(voicing: notes)
    }
}
