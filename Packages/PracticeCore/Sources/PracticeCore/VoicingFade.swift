import TheoryCore

/// How a triad's voicing fades while it is played, unpaced (ADR 0007): the part of the triad drills that fades. Its
/// notes but the root start fully shown and fade out over the voicing's fade time, from when its first note's timer
/// starts; the level is its shape's (`FadeLevels.VoicingShape`), whatever the root. Level 0 never fades and isn't
/// timed, so a new shape can be learned as slowly as it needs.
///
/// A drill keeps one, and tells it when a voicing is up (`start`), when a prompt's timer starts, about hints, and each
/// attempt dealt with; it stamps the facts logged and gives the fade to draw (`noteFade`).
struct VoicingFade: Sendable {
    /// What an unpaced voicing should take, which its fade time is a share of.
    static let expectedTime: Duration = .seconds(10)

    /// This run's voicings included.
    var reached: FadeLevels

    private let override: FadeLevel?
    private let tuning: Tuning
    private let expected: Duration
    /// What the voicing that is up is played at.
    private(set) var level = FadeLevel.first
    /// When its first note's timer started.
    private var start: Duration = .zero
    private var isHinted = false
    /// H is held.
    private var isHintShown = false
    /// The voicing's, since it last started.
    private var notes: [FadeLevels.VoicingNote] = []

    init(setup: DrillSetup, expected: Duration = VoicingFade.expectedTime) {
        reached = setup.fadeLevels
        override = setup.options.triadFade
        tuning = setup.fretboard.tuning
        self.expected = expected
    }

    /// Level 0 can be taken as slowly as it needs to be learned.
    var isTimed: Bool { level != .first }

    /// How the notes that aren't the root fade now: not at all during a hint.
    var noteFade: NoteFade {
        isHintShown ? .none : NoteFade(level: level, expected: expected, start: start)
    }

    /// A voicing is up, from its lowest note.
    mutating func start(_ facts: TriadFacts) {
        level = override ?? reached.level(of: FadeLevels.VoicingShape(facts, in: tuning))
        isHinted = isHintShown
        notes = []
    }

    /// A prompt's timer started, or was put off: until a note of the voicing is dealt with, the fade starts then.
    mutating func timerStarted(at time: Duration) {
        if notes.isEmpty { start = time }
    }

    mutating func hint(isShown: Bool) {
        isHintShown = isShown
        if isShown { isHinted = true }
    }

    /// As they are logged.
    func logged(_ facts: TriadFacts) -> TriadFacts {
        var facts = facts
        facts.fadeLevel = level
        facts.hinted = isHinted
        return facts
    }

    /// Counts a note that was dealt with; the voicing's last counts the voicing.
    mutating func dealtWith(_ attempt: Attempt) {
        guard let note = FadeLevels.VoicingNote(attempt, in: tuning) else { return }
        notes.append(note)
        // Nothing is counted until the voicing is over.
        reached.add(voicing: notes)
    }
}
