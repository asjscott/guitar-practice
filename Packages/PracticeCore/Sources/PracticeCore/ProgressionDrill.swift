import TheoryCore

/// The engine of the progression drills: the progression round and round over backing, each chord's triad arpeggiated
/// low to high while it sounds, and scored clean, wrong or missed. What each chord expects is up to the rules. It
/// records one attempt per chord; the chords of a time through share a group, and a time through started again on
/// Resume is a new one.
///
/// Times are on the drill's clock, the backing's as heard. A chord's window runs from half a beat before its first
/// beat to the end of its last. Onsets have the input delay taken off first. In the half beat where two windows meet,
/// a note goes on with the chord before if it can, and otherwise begins the next. Once a voicing is finished, notes
/// are ignored until the next window opens; a note played again at once (the same pitch twice) is ignored too.
///
/// The fade is per run: Shown for times through 1–2, Faded for 3–4, then Hidden; in Hidden, a time through with a
/// chord that isn't clean makes the next one Faded. H held shows the voicing, and the chord isn't clean. Skip does
/// nothing; pausing stops the backing, and Resume starts that time through again after a count-in.
public struct ProgressionDrill<Rules: ProgressionRules>: Drill {
    public private(set) var phase: DrillPhase = .idle
    public private(set) var attempts: [Attempt] = []
    public let setup: DrillSetup

    /// The chord being scored, or about to be.
    private struct OpenChord {
        /// Counting chords from this backing's first time through.
        let slot: Int
        let expected: ExpectedVoicings
        var hinted: Bool
        /// Every note taken, in order.
        var notes: [Pitch] = []
        /// The notes since the last wrong one that begin an accepted voicing.
        var match: [Pitch] = []
        var wrong: [Pitch] = []
        var played: TriadVoicing?
        /// Set once the voicing is finished.
        var outcome: ChordOutcome?
        var firstOnset: Duration?

        var isFinished: Bool { outcome != nil }
    }

    private let key: Key
    private let progression: Progression?
    private let position: Position?
    private let chords: [Triad]
    /// Each chord's voicings in the position, and on the whole neck.
    private let inPosition: [[TriadVoicing]]
    private let anywhere: [[TriadVoicing]]
    /// Bars before each chord in a time through.
    private let barsBefore: [Int]
    /// The rules' top-note line, if they have one.
    private let topNotes: [Pitch]?
    private var settings: BackingSettings { setup.options.backing }

    /// As heard.
    private var backing: Backing
    private var pendingBacking: [BackingRequest] = []
    private var now: Duration = .zero

    private var open: OpenChord?
    /// The run's time through `open` is in, from 0.
    private var timeThrough = 0
    /// The slot `timeThrough` began at.
    private var timeThroughStart = 0
    /// This time through's chords so far.
    private var outcomes: [ChordOutcome?] = []
    private var group = -1
    /// Times through played to the end.
    private var completed = 0
    private var stage = FadeStage.shown
    private var previousPlayed: TriadVoicing?
    private var previousDrawn: TriadVoicing?
    private var isHintShown = false
    /// How the last time through went: "3 of 4 clean".
    private var lastTimeThroughText: String?

    public init(setup: DrillSetup) {
        self.setup = setup
        key = setup.chosenKey
        progression = setup.options.progression
        position = setup.progressionPosition
        let chords = progression?.chords(in: key) ?? []
        self.chords = chords
        let fretboard = setup.fretboard
        inPosition = position.map { position in chords.map { fretboard.voicings(of: $0, in: position) } } ?? []
        anywhere = chords.map { chord in
            fretboard.stringSets.flatMap { set in
                Triad.Inversion.allCases.flatMap { fretboard.voicings(of: chord, inversion: $0, on: set) }
            }
        }
        let bars = progression?.steps.map(\.bars) ?? []
        barsBefore = bars.indices.map { bars[..<$0].reduce(0, +) }
        if let progression = setup.options.progression, let position = setup.progressionPosition {
            topNotes = Rules.topNotes(of: progression, in: setup.chosenKey, position: position, on: fretboard)
        } else {
            topNotes = nil
        }
        backing = Backing(chords: [BackingChord(Triad(.major, root: .c))], style: setup.options.backing.style,
                          bpm: setup.options.backing.tempo, start: .zero)
    }

    // MARK: - State

    public var kind: DrillKind { Rules.kind }
    public var timeLimit: Duration { .seconds(5) }
    public func timeRemaining(at now: Duration) -> Duration? { nil }
    public var promptStart: Duration? { nil }
    public var canHold: Bool { false }
    public var resumesSamePrompt: Bool { phase == .paused }

    public var nothingToPromptReason: String? { setup.progressionProblem }

    /// The chord on the neck: its root, where the voicing has it.
    public var prompt: NotePrompt? {
        guard isRunning, phase != .paused, let neck else { return nil }
        return rootPrompt(of: neck.voicing)
    }

    private func rootPrompt(of voicing: TriadVoicing) -> NotePrompt {
        let root = voicing.triad.root
        let location = voicing.locations.first { fretboard.pitch(at: $0).pitchClass == root.pitchClass }
            ?? voicing.locations[0]
        return NotePrompt(name: root, string: location.string, target: location)
    }

    public mutating func takeSounds() -> [DrillSoundRequest] { [] }

    public mutating func takeBacking() -> [BackingRequest] {
        defer { pendingBacking = [] }
        return pendingBacking
    }

    private var count: Int { chords.count }
    private var beat: Duration { .seconds(60) / settings.tempo }
    private var halfBeat: Duration { beat / 2 }

    /// When a chord's first beat is heard.
    private func start(ofSlot slot: Int) -> Duration {
        let bars = 1 + slot / count * (progression?.bars ?? 0) + barsBefore[slot % count]
        return backing.time(ofEighth: bars * Backing.beatsPerBar * 2)
    }

    private func end(ofSlot slot: Int) -> Duration { start(ofSlot: slot + 1) }

    // MARK: - Events

    public mutating func handle(_ event: DrillEvent) {
        switch event {
        case .start(let now):
            guard !isRunning, nothingToPromptReason == nil else { return }
            attempts = []
            completed = 0
            timeThrough = 0
            stage = .shown
            lastTimeThroughText = nil
            begin(at: now)
        case .pause(let now):
            advance(to: now)
            guard isRunning, phase != .paused else { return }
            phase = .paused
            open = nil
            isHintShown = false
            pendingBacking = [.stop]
        case .resume(let now):
            guard phase == .paused else { return }
            begin(at: now)
        case .stop:
            guard isRunning else { return }
            phase = .idle
            open = nil
            isHintShown = false
            pendingBacking = [.stop]
        case .played(let pitch, let onset, let now):
            guard isRunning, phase != .paused else { return }
            let onset = onset - setup.inputDelay
            advance(to: onset, grace: .zero)
            take(pitch, onset: onset)
            advance(to: now)
        case .hint(let isShown, let now):
            advance(to: now)
            guard isRunning, phase != .paused else { return }
            isHintShown = isShown
            if isShown, open?.isFinished == false { open?.hinted = true }
        case .backingStarted(let heard):
            backing = heard
        case .tick(let now):
            advance(to: now)
        case .skip(let now), .repeat(let now):
            advance(to: now)
        case .typed, .soundStarted, .hold, .clicksStarted, .passSettings, .fadeStages:
            break
        }
    }

    /// The time through `timeThrough`, from its first chord, after a count-in.
    private mutating func begin(at now: Duration) {
        self.now = max(self.now, now)
        guard let progression else { return }
        backing = Backing(chords: zip(chords, progression.steps).map { BackingChord($0, bars: $1.bars) },
                          style: settings.style, bpm: settings.tempo, start: now)
        pendingBacking = [.start(backing)]
        previousPlayed = nil
        previousDrawn = nil
        outcomes = Array(repeating: nil, count: count)
        group += 1
        phase = .waiting
        open = nil
        timeThroughStart = 0
        open(slot: 0)
    }

    /// Moves the clock to `now`: chords whose window ended `grace` ago are scored.
    private mutating func advance(to now: Duration, grace: Duration = DrillTiming.detectionGrace) {
        self.now = max(self.now, now)
        while let chord = open, phase != .paused, now >= end(ofSlot: chord.slot) + grace {
            close()
        }
    }

    // MARK: - Chords

    private func turn(slot: Int, previousPlayed: TriadVoicing?, previousDrawn: TriadVoicing?) -> ChordTurn {
        ChordTurn(fretboard: fretboard, position: position!, chords: chords, index: slot % count,
                  timeThrough: timeThrough + (slot - timeThroughStart) / count, voicings: inPosition[slot % count],
                  previousPlayed: previousPlayed, previousDrawn: previousDrawn, topNote: topNotes?[slot % count])
    }

    private mutating func open(slot: Int) {
        let expected = Rules.expected(for: turn(slot: slot, previousPlayed: previousPlayed, previousDrawn: previousDrawn))
        open = OpenChord(slot: slot, expected: expected, hinted: isHintShown)
    }

    /// Scores the open chord and opens the next.
    private mutating func close() {
        guard let chord = open else { return }
        let index = chord.slot % count
        let outcome = chord.outcome ?? (chord.wrong.isEmpty ? .missed : .wrong)
        record(chord, outcome: outcome)
        outcomes[index] = outcome
        previousPlayed = outcome == .missed ? nil : chord.played
        previousDrawn = chord.played ?? chord.expected.drawn
        let next = chord.slot + 1
        if index == count - 1 {
            endTimeThrough()
            timeThroughStart = next
        }
        open(slot: next)
    }

    private mutating func endTimeThrough() {
        let isClean = outcomes.allSatisfy { $0 == .clean }
        let clean = outcomes.filter { $0 == .clean }.count
        lastTimeThroughText = "\(clean) of \(count) clean"
        completed += 1
        stage = switch completed {
        case ..<2: .shown
        case ..<4: .faded
        default: stage == .hidden && !isClean ? .faded : .hidden
        }
        timeThrough += 1
        group += 1
        outcomes = Array(repeating: nil, count: count)
    }

    /// Whether a note goes on with the open chord's voicing.
    private func continues(_ chord: OpenChord, with pitch: Pitch) -> Bool {
        !chord.isFinished && (pitch == chord.notes.last || isPrefix(chord.match + [pitch], of: chord))
    }

    private func isPrefix(_ pitches: [Pitch], of chord: OpenChord) -> Bool {
        chord.expected.accepted.contains { Array(self.pitches(of: $0).prefix(pitches.count)) == pitches }
    }

    private func pitches(of voicing: TriadVoicing) -> [Pitch] { voicing.locations.map(fretboard.pitch) }

    private mutating func take(_ pitch: Pitch, onset: Duration) {
        guard let chord = open, onset >= start(ofSlot: chord.slot) - halfBeat else { return }
        if onset >= end(ofSlot: chord.slot) - halfBeat, !continues(chord, with: pitch) {
            close()
            guard let next = open, onset >= start(ofSlot: next.slot) - halfBeat else { return }
        }
        guard var chord = open, !chord.isFinished, pitch != chord.notes.last else { return }
        defer { open = chord }
        chord.notes.append(pitch)
        if chord.firstOnset == nil { chord.firstOnset = onset - start(ofSlot: chord.slot) }
        if isPrefix(chord.match + [pitch], of: chord) {
            chord.match.append(pitch)
        } else {
            chord.wrong.append(pitch)
            chord.match = isPrefix([pitch], of: chord) ? [pitch] : []
        }
        if chord.match.count == 3 {
            chord.played = chord.expected.accepted.first { pitches(of: $0) == chord.match }
            chord.outcome = chord.wrong.isEmpty && !chord.hinted ? .clean : .wrong
        } else if chord.notes.count >= 3, let other = voicing(of: chord.slot % count, playing: chord.notes.suffix(3)) {
            chord.played = other
            chord.outcome = .wrong
        }
    }

    /// A voicing of a chord with these pitches, low to high: one in the position if there is one.
    private func voicing(of index: Int, playing notes: ArraySlice<Pitch>) -> TriadVoicing? {
        let notes = Array(notes)
        return inPosition[index].first { pitches(of: $0) == notes } ?? anywhere[index].first { pitches(of: $0) == notes }
    }

    private mutating func record(_ chord: OpenChord, outcome: ChordOutcome) {
        guard let progression, let position else { return }
        let index = chord.slot % count
        let played = outcome == .missed ? nil : chord.played
        let facts = ChordFacts(progression: progression, key: key, place: index, triad: chords[index],
                               position: position.id, played: played, accepted: chord.expected.accepted,
                               style: settings.style, tempo: settings.tempo, fadeStage: stage, hinted: chord.hinted,
                               outcome: outcome, firstOnset: chord.firstOnset, inputDelay: setup.inputDelay)
        // The prompt is the chord's root in the voicing played, or else the one drawn.
        attempts.append(Attempt(prompt: rootPrompt(of: played ?? chord.expected.drawn),
                                outcome: outcome == .missed ? .timedOut : .answered,
                                wrongAnswers: chord.wrong.map { .pitch($0) },
                                group: AttemptGroup(number: group, size: count, place: index), facts: .chord(facts)))
    }

    // MARK: - Display

    /// The chord on the neck: the open one, or from half a beat before its window ends, the next.
    private var neck: (slot: Int, voicing: TriadVoicing, played: Int, chord: OpenChord?)? {
        guard let chord = open else { return nil }
        if now >= end(ofSlot: chord.slot) - halfBeat {
            let next = Rules.expected(for: turn(slot: chord.slot + 1, previousPlayed: chord.played,
                                                previousDrawn: chord.played ?? chord.expected.drawn))
            return (chord.slot + 1, next.drawn, 0, nil)
        }
        let isDrawnBegun = Array(pitches(of: chord.expected.drawn).prefix(chord.match.count)) == chord.match
        let voicing = chord.played ?? (isDrawnBegun ? nil
            : chord.expected.accepted.first { Array(pitches(of: $0).prefix(chord.match.count)) == chord.match })
            ?? chord.expected.drawn
        return (chord.slot, voicing, chord.isFinished ? 3 : chord.match.count, chord)
    }

    public var display: DrillDisplay? {
        guard isRunning, phase != .paused, let neck, let progression, let position else { return nil }
        let shownStage = isHintShown ? .shown : stage
        let (result, feedback) = resultAndFeedback(of: neck.chord)
        var display = DrillDisplay(headline: chords.map(\.shortName).joined(separator: "  "),
                                   subline: "\(progression.name) in \(key.shortName) · \(position.name)",
                                   feedback: feedback, result: result,
                                   markers: markers(of: neck.voicing, played: neck.played, stage: shownStage,
                                                    slot: neck.slot))
        if shownStage != .hidden { display.highlightedStrings = Set(neck.voicing.stringSet.strings) }
        display.progression = progress(fretWindow: position.fretWindow)
        return display
    }

    private func resultAndFeedback(of chord: OpenChord?) -> (DrillDisplay.Result, String) {
        if isCountingIn { return (.waiting, lastTimeThroughText ?? "Play each chord low to high, one note at a time") }
        guard let chord else { return (.waiting, "Listening…") }
        let name = chords[chord.slot % count].shortName
        switch chord.outcome {
        case .clean: return (.right, "\(name): clean")
        case .wrong where chord.played != nil && chord.wrong.isEmpty: return (.wrong, "\(name): hinted")
        case .wrong where chord.played != nil && !chord.expected.accepted.contains(chord.played!):
            return (.wrong, "Another voicing of \(name)")
        default:
            guard let wrong = chord.wrong.last else { return (.waiting, "Listening…") }
            return (.wrong, "You played \(key.spell(wrong.pitchClass))")
        }
    }

    private var isCountingIn: Bool { open?.slot == 0 && now < start(ofSlot: 0) }

    /// The voicing's notes played so far solid, the last ringed; the rest as the stage shows (Shown during a hint).
    /// While the run is at Shown, the next chord's voicing is ghosted.
    private func markers(of voicing: TriadVoicing, played: Int, stage: FadeStage, slot: Int) -> [DrillDisplay.Marker] {
        var markers = voicing.locations.enumerated().compactMap { index, location -> DrillDisplay.Marker? in
            let isPlayed = index < played
            guard isPlayed || stage != .hidden else { return nil }
            return marker(location, of: voicing.triad, isFaint: !isPlayed && stage == .faded,
                          isLast: isPlayed && index == played - 1)
        }
        if self.stage == .shown {
            let next = Rules.expected(for: turn(slot: slot + 1, previousPlayed: voicing, previousDrawn: voicing)).drawn
            markers += next.locations.filter { !voicing.locations.contains($0) }.map {
                marker($0, of: next.triad, isFaint: true, isLast: false)
            }
        }
        return markers
    }

    private func marker(_ location: FretboardLocation, of triad: Triad, isFaint: Bool, isLast: Bool) -> DrillDisplay.Marker {
        let pitchClass = fretboard.pitch(at: location).pitchClass
        let name = triad.notes.first { $0.pitchClass == pitchClass } ?? key.spell(pitchClass)
        return DrillDisplay.Marker(location: location, label: isFaint ? "" : name.description,
                                   isAnswer: pitchClass == triad.root.pitchClass, isFaint: isFaint, isLastPlayed: isLast)
    }

    private func progress(fretWindow: ClosedRange<Int>) -> ProgressionProgress? {
        guard let progression, let chord = open else { return nil }
        let first = chord.slot / count * count
        let beats = progression.steps.map { $0.bars * Backing.beatsPerBar }
        let beat = (now - start(ofSlot: first)) / self.beat
        let blocks = zip(chords, progression.steps).enumerated().map { index, pair in
            ProgressionProgress.Block(name: pair.0.shortName, numeral: pair.1.numeral.text, beats: beats[index],
                                      outcome: outcomes[index])
        }
        let current = beat < 0 ? nil : barsBefore.indices.last { Double(barsBefore[$0] * Backing.beatsPerBar) <= beat }
        var countIn: Int?
        if isCountingIn, now >= backing.start { countIn = min(4, Int((now - backing.start) / self.beat) + 1) }
        let topNotes = topNotes.map { line in
            zip(chords, line).map { chord, pitch in
                let name = chord.notes.first { $0.pitchClass == pitch.pitchClass } ?? key.spell(pitch.pitchClass)
                return ProgressionProgress.TopNote(name: name.description, pitch: pitch)
            }
        }
        return ProgressionProgress(blocks: blocks, current: current, beat: beat, timeThrough: timeThrough + 1,
                                   fadeStage: stage, countIn: countIn, tempo: settings.tempo,
                                   fretWindow: fretWindow, topNotes: topNotes)
    }
}
