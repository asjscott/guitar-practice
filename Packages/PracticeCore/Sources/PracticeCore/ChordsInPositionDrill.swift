import TheoryCore

extension DrillKind {
    public static let chordsInPosition = DrillKind(
        id: "chordsInPosition", module: .progressions, title: "Chords in position",
        instructions: "Play each chord low to high in the voicing shown, in your own time; each time through moves up.",
        symbol: "square.stack.3d.up.badge.automatic", traits: [], repeatTitle: nil) {
            ChordsInPositionDrill(setup: $0)
        }
}

/// Chords in position: the progression's chords in order, with no backing and no clock, each expecting Stay in
/// position's voicing for that time through (time through *k*, voicing *k*), so the path is known before the band
/// starts. Each voicing fades at its shape's level over 10 s from when its chord comes up (`VoicingFade`); level 0
/// doesn't fade. Chords don't move the levels.
///
/// A voicing is played low to high; a wrong note leaves the next note to play where it was, and the lowest note
/// starts the voicing again. Once its third note is played the chord is scored, clean with no wrong note and no hint,
/// and the next comes up shortly. Skip scores it as not clean and moves on. One attempt per chord, the chords of a time
/// through sharing a group, as in the progression drills, with no backing in its facts.
///
/// It ends by itself once each chord of the progression has been clean twice, or, once 3 minutes have been played
/// (pauses not counted), after the chord that is up. Pausing hides the chord; Resume brings it up again from its first
/// note.
public struct ChordsInPositionDrill: Drill {
    /// Each chord's clean voicings it takes to end.
    public static let cleanTimes = 2
    /// Played for this long, it ends after the chord that is up.
    public static let maximumTime: Duration = .seconds(180)

    public private(set) var phase: DrillPhase = .idle
    public private(set) var attempts: [Attempt] = []
    public let setup: DrillSetup

    private let key: Key
    private let progression: Progression?
    private let position: Position?
    private let chords: [Triad]
    private let inPosition: [[TriadVoicing]]

    private var fade: VoicingFade
    private var now: Duration = .zero
    /// Played before the last start or resume.
    private var playedBefore: Duration = .zero
    private var runningSince: Duration = .zero

    /// The chord up, counting from the run's first.
    private var slot = 0
    private var voicing: TriadVoicing?
    /// When the chord came up.
    private var chordStart: Duration = .zero
    /// Its notes played so far, as for a triad's display.
    private var notes: [Attempt] = []
    private var wrong: [Pitch] = []
    private var wrongSinceNote: [WrongAnswer] = []
    private var lastPitch: Pitch?
    private var firstOnset: Duration?
    /// Once the chord is scored, when the next comes up.
    private var nextAt: Duration?
    private var cleanCounts: [Int] = []

    public init(setup: DrillSetup) {
        self.setup = setup
        key = setup.chosenKey
        progression = setup.options.progression
        position = setup.progressionPosition
        let chords = progression?.chords(in: key) ?? []
        self.chords = chords
        let fretboard = setup.fretboard
        inPosition = position.map { position in chords.map { fretboard.voicings(of: $0, in: position) } } ?? []
        fade = VoicingFade(setup: setup)
    }

    // MARK: - State

    public var kind: DrillKind { .chordsInPosition }
    public var timeLimit: Duration { VoicingFade.expectedTime }
    public func timeRemaining(at now: Duration) -> Duration? { nil }
    public var promptStart: Duration? { isUp ? chordStart : nil }
    public var canHold: Bool { false }
    public var resumesSamePrompt: Bool { phase == .paused }
    public var isPartWay: Bool { isUp && !notes.isEmpty && nextAt == nil }
    public var fadeLevels: FadeLevels? { fade.reached }

    public var nothingToPromptReason: String? {
        if let problem = setup.progressionProblem { return problem }
        return inPosition.contains { $0.isEmpty } ? "A chord has no voicing in the position: choose another position."
            : nil
    }

    private var isUp: Bool { isRunning && phase != .paused && voicing != nil }
    private var count: Int { chords.count }
    private var index: Int { slot % count }
    private var timeThrough: Int { slot / count }

    /// The next note to play, on its string.
    public var prompt: NotePrompt? {
        guard isUp, let voicing else { return nil }
        return notePrompt(voicing, min(notes.count, 2))
    }

    private func notePrompt(_ voicing: TriadVoicing, _ note: Int) -> NotePrompt {
        let location = fretboard.locationsLowToHigh(of: voicing)[note]
        let pitchClass = fretboard.pitch(at: location).pitchClass
        let name = voicing.triad.notes.first { $0.pitchClass == pitchClass } ?? key.spell(pitchClass)
        return NotePrompt(name: name, string: location.string, target: location)
    }

    public mutating func takeSounds() -> [DrillSoundRequest] { [] }

    // MARK: - Events

    public mutating func handle(_ event: DrillEvent) {
        switch event {
        case .start(let now):
            guard !isRunning, nothingToPromptReason == nil else { return }
            self.now = now
            attempts = []
            cleanCounts = Array(repeating: 0, count: count)
            playedBefore = .zero
            runningSince = now
            bringUp(slot: 0)
        case .pause(let now):
            advance(to: now)
            guard isRunning, phase != .paused else { return }
            fade.hint(isShown: false)
            // A chord already scored is behind: the next is the one to resume.
            if nextAt != nil { moveOn() }
            guard isRunning else { return }
            playedBefore += self.now - runningSince
            phase = .paused
        case .resume(let now):
            guard phase == .paused else { return }
            self.now = max(self.now, now)
            runningSince = self.now
            bringUp(slot: slot)
        case .stop:
            phase = .idle
            voicing = nil
        case .played(let pitch, let onset, let now):
            advance(to: now)
            guard isUp, nextAt == nil else { return }
            take(pitch, onset: onset - setup.inputDelay)
        case .hint(let isShown, let now):
            advance(to: now)
            guard isRunning, phase != .paused else { return }
            fade.hint(isShown: isShown)
        case .skip(let now):
            advance(to: now)
            guard isUp, nextAt == nil else { return }
            score(skipped: true)
            moveOn()
        case .tick(let now), .repeat(let now):
            advance(to: now)
        case .fadeLevels(let new):
            fade.reached = new
        case .typed, .soundStarted, .hold, .clicksStarted, .backingStarted, .passSettings:
            break
        }
    }

    private mutating func advance(to now: Duration) {
        self.now = max(self.now, now)
        if let nextAt, self.now >= nextAt, phase != .paused { moveOn() }
    }

    private var playedTime: Duration { playedBefore + (phase == .paused ? .zero : now - runningSince) }

    /// After a chord: the next, or the end.
    private mutating func moveOn() {
        nextAt = nil
        let isDone = cleanCounts.allSatisfy { $0 >= Self.cleanTimes } || playedTime >= Self.maximumTime
        if isDone {
            phase = .idle
            voicing = nil
        } else {
            bringUp(slot: slot + 1)
        }
    }

    private mutating func bringUp(slot: Int) {
        self.slot = slot
        let turn = ChordTurn(fretboard: fretboard, position: position!, chords: chords, index: slot % count,
                             timeThrough: slot / count, voicings: inPosition[slot % count], previousPlayed: nil,
                             previousDrawn: nil)
        guard let voicing = StayInPositionRules.expected(for: turn)?.drawn else {
            phase = .idle
            return
        }
        self.voicing = voicing
        phase = .waiting
        chordStart = now
        notes = []
        wrong = []
        wrongSinceNote = []
        lastPitch = nil
        firstOnset = nil
        nextAt = nil
        fade.start(Self.facts(of: voicing))
        fade.timerStarted(at: now)
    }

    private static func facts(of voicing: TriadVoicing) -> TriadFacts {
        TriadFacts(triad: voicing.triad, inversion: voicing.inversion, stringSet: voicing.stringSet)
    }

    private mutating func take(_ pitch: Pitch, onset: Duration) {
        guard let voicing, onset >= chordStart, pitch != lastPitch else { return }
        lastPitch = pitch
        if firstOnset == nil { firstOnset = onset - chordStart }
        let pitches = fretboard.pitches(of: voicing)
        let locations = fretboard.locationsLowToHigh(of: voicing)
        if pitch == pitches[notes.count] || pitch == pitches[0] {
            // The lowest note, played again, starts the voicing again.
            if pitch == pitches[0] { notes = [] }
            let note = notes.count
            notes.append(Attempt(prompt: notePrompt(voicing, note), outcome: .answered,
                                 responseTime: onset - (notes.isEmpty ? chordStart : lastNoteOnset),
                                 wrongAnswers: wrongSinceNote, location: locations[note]))
            lastNoteOnset = onset
            wrongSinceNote = []
            phase = .correct(locations[note])
            if notes.count == pitches.count {
                score(skipped: false)
                nextAt = now + DrillTiming.correctPause
            }
        } else {
            wrong.append(pitch)
            wrongSinceNote.append(.pitch(pitch))
            phase = .wrong(pitch.pitchClass)
        }
    }

    private var lastNoteOnset: Duration = .zero

    private mutating func score(skipped: Bool) {
        guard let progression, let position, let voicing else { return }
        let hinted = fade.logged(Self.facts(of: voicing)).hinted
        let isComplete = notes.count == 3
        let outcome: ChordOutcome = isComplete && wrong.isEmpty && !hinted ? .clean
            : isComplete || !wrong.isEmpty || hinted ? .wrong : .missed
        if outcome == .clean { cleanCounts[index] += 1 }
        let facts = ChordFacts(progression: progression, key: key, place: index, triad: chords[index],
                               position: position.id, played: isComplete ? voicing : nil, accepted: [voicing],
                               style: nil, tempo: nil, fadeLevel: fade.level, hinted: hinted, outcome: outcome,
                               firstOnset: firstOnset, inputDelay: setup.inputDelay)
        attempts.append(Attempt(prompt: notePrompt(voicing, 0), outcome: skipped ? .skipped : .answered,
                                responseTime: skipped ? nil : notes.compactMap(\.responseTime).reduce(.zero, +),
                                wrongAnswers: wrong.map { .pitch($0) },
                                location: skipped ? nil : fretboard.locationsLowToHigh(of: voicing)[0],
                                group: AttemptGroup(number: timeThrough, size: count, place: index),
                                facts: .chord(facts)))
    }

    // MARK: - Display

    /// The voicing as a triad's: the notes played solid, the root solid, the rest as they fade. The headline is the
    /// chord; a chip per chord of the progression, done once clean twice.
    public var display: DrillDisplay? {
        guard isUp, let voicing, let progression, let position, let prompt else { return nil }
        let moment = DrillMoment(prompt: prompt, phase: phase, isHeld: false, wrongAnswers: wrongSinceNote,
                                 attempts: notes, correctLocations: voicing.locations, now: now, promptStart: chordStart)
        var display = DrillDisplay(triad: Self.facts(of: voicing), at: fretboard.locationsLowToHigh(of: voicing),
                                   played: notes, fading: fade.noteFade, moment: moment, in: setup)
        display.headline = chords[index].shortName
        display.subline = "\(progression.steps[index].numeral.text) · \(position.name) · "
            + "\((timeThrough + 1).ordinal) time through · \(fade.level)"
        if nextAt != nil, let last = attempts.last?.chord {
            display.result = last.outcome == .clean ? .right : .wrong
            display.feedback = last.outcome == .clean ? "Clean · \(display.feedback)" : last.hinted ? "Hinted" : "Not clean"
        }
        display.chips = chords.indices.map { chord in
            let name = chords[chord].shortName
            let numeral = progression.steps[chord].numeral.text
            let state: DrillDisplay.Chip.State = chord == index ? .current
                : cleanCounts[chord] >= Self.cleanTimes ? .found : .waiting
            return DrillDisplay.Chip(title: numeral, spokenTitle: "\(numeral), \(name), clean \(cleanCounts[chord]) of "
                                     + "\(Self.cleanTimes)", text: name, state: state)
        }
        return display
    }
}
