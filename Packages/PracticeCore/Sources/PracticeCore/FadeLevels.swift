import TheoryCore

/// The fade level each subject has reached, worked out from the log and never stored (ADR 0007). A subject moves at
/// most one level a session (in free practice, a run): up from 0 if every prompt of it was clean, down if any wasn't.
/// Its prompts are played at the level reached before the run, and one played at another level doesn't count. Each
/// drill that fades keeps one per kind of subject, and decides what makes a prompt complete and clean.
public struct FadeLadder<Subject: Hashable & Sendable>: Hashable, Sendable {
    private var levels: [Subject: FadeLevel] = [:]
    /// The run's counted prompts of each subject: whether all were clean, and the levels it moves between.
    private var run: [Subject: RunCount] = [:]

    private struct RunCount: Hashable, Sendable {
        var isClean: Bool
        var steps: [FadeLevel]
    }

    public init() {}

    /// What its prompts are played at: the level reached before this run.
    public func level(of subject: Subject) -> FadeLevel { levels[subject] ?? .first }

    /// Where this run takes it: one up if every prompt counted was clean, one down if any wasn't.
    public func levelAfterRun(of subject: Subject) -> FadeLevel {
        let reached = level(of: subject)
        guard let count = run[subject] else { return reached }
        return count.isClean ? count.steps.first { $0 > reached } ?? reached : count.steps.last { $0 < reached } ?? .first
    }

    /// Every subject counted so far; any other is at the first level.
    var subjects: Set<Subject> { Set(levels.keys).union(run.keys) }

    /// Counts a complete prompt of this run. `steps` are the levels it moves between: all of them, unless it was logged
    /// at a fade stage (`FadeLevel.stageSteps`).
    public mutating func count(_ subject: Subject, playedAt played: FadeLevel, isClean: Bool,
                               steps: [FadeLevel] = FadeLevel.all) {
        guard played == level(of: subject) else { return }
        run[subject] = RunCount(isClean: isClean && run[subject]?.isClean != false, steps: run[subject]?.steps ?? steps)
    }

    /// The run is over: each subject counted moves to its level after it.
    public mutating func endRun() {
        for subject in run.keys { levels[subject] = levelAfterRun(of: subject) }
        run = [:]
    }
}

extension FadeLevel {
    /// The levels the old fade stages moved between: Shown, Faded and Hidden.
    public static let stageSteps = FadeStage.allCases.map(FadeLevel.init)
}

/// The fade levels reached in the scale and triad drills, from the logged passes and voicings: each scale kind in
/// each position, and each shape of triad voicing, moving at most one level a run (`FadeLadder`). A session is one run.
/// Passes that aren't complete don't count.
public struct FadeLevels: Hashable, Sendable {
    /// What a pass's level belongs to, whatever the key, capo and octave.
    public struct Subject: Hashable, Sendable {
        public var tuning: Tuning
        public var scaleKind: Scale.Kind
        /// Its octave is ignored.
        public var position: Position.ID

        public init(tuning: Tuning, scaleKind: Scale.Kind, position: Position.ID) {
            self.tuning = tuning
            self.scaleKind = scaleKind
            self.position = position
        }

        fileprivate var lowest: Subject {
            Subject(tuning: tuning, scaleKind: scaleKind, position: Position.ID(system: position.system, number: position.number))
        }
    }

    /// What a triad's level belongs to, whatever its root, frets and capo.
    public struct VoicingShape: Hashable, Sendable {
        public var tuning: Tuning
        public var quality: Triad.Quality
        public var inversion: Triad.Inversion
        public var stringSet: StringSet

        public init(tuning: Tuning, quality: Triad.Quality, inversion: Triad.Inversion, stringSet: StringSet) {
            self.tuning = tuning
            self.quality = quality
            self.inversion = inversion
            self.stringSet = stringSet
        }

        init(_ facts: TriadFacts, in tuning: Tuning) {
            self.init(tuning: tuning, quality: facts.triad.quality, inversion: facts.inversion, stringSet: facts.stringSet)
        }
    }

    private(set) var passes = FadeLadder<Subject>()
    private(set) var voicings = FadeLadder<VoicingShape>()

    public init() {}

    /// From logged notes, oldest first, each with its group: a pass's, and those of triads' voicings. Each pass and
    /// voicing is a run of its own, as before runs were logged.
    public init<Group: Hashable>(log: [(group: Group, note: Note)], voicings: [(group: Group, note: VoicingNote)] = []) {
        self.init(runs: log.map { (run: Int?.none, group: $0.group, note: $0.note) },
                  voicings: voicings.map { (run: Int?.none, group: $0.group, note: $0.note) })
    }

    /// From logged notes, oldest first, each with its run (a session's, or a run's in free practice) and its group: a
    /// pass's, and those of triads' voicings. A climb's voicings share a group, and a voicing that was started again is
    /// a new one. A note without a run is in a run of its pass or voicing alone. The runs are counted in the order they
    /// ended, `current` last; it is left going, so that its prompts still play at the levels reached before it.
    public init<Run: Hashable, Group: Hashable>(runs log: [(run: Run?, group: Group, note: Note)],
                                                voicings: [(run: Run?, group: Group, note: VoicingNote)] = [],
                                                current: Run? = nil) {
        var groups: [Group] = []
        var passes: [Group: [Note]] = [:]
        var passRuns: [Group: Run?] = [:]
        var passEnds: [Group: Int] = [:]
        for (index, entry) in log.enumerated() {
            if passes[entry.group] == nil {
                groups.append(entry.group)
                passRuns[entry.group] = entry.run
            }
            passes[entry.group, default: []].append(entry.note)
            passEnds[entry.group] = index
        }
        let passPrompts = groups.map { group in
            (run: passRuns[group] ?? nil, end: passEnds[group] ?? 0, notes: passes[group] ?? [])
        }
        for run in Self.inRuns(passPrompts, current: current) {
            for pass in run.prompts { add(pass) }
            if !run.isCurrent { self.passes.endRun() }
        }

        var voicingPrompts: [(run: Run?, end: Int, notes: [VoicingNote])] = []
        var voicingGroup: Group?
        for (index, entry) in voicings.enumerated() {
            if entry.note.place == 0 || entry.group != voicingGroup || voicingPrompts.isEmpty {
                voicingPrompts.append((entry.run, index, []))
                voicingGroup = entry.group
            }
            voicingPrompts[voicingPrompts.count - 1].notes.append(entry.note)
            voicingPrompts[voicingPrompts.count - 1].end = index
        }
        for run in Self.inRuns(voicingPrompts, current: current) {
            for voicing in run.prompts { add(voicing: voicing) }
            if !run.isCurrent { self.voicings.endRun() }
        }
    }

    /// Prompts gathered into their runs, each run's in order, the runs in the order they ended with `current` last.
    private static func inRuns<Run: Hashable, Prompt>(_ prompts: [(run: Run?, end: Int, notes: Prompt)], current: Run?)
        -> [(prompts: [Prompt], isCurrent: Bool)] {
        var keys: [RunKey<Run>] = []
        var byRun: [RunKey<Run>: (end: Int, prompts: [Prompt])] = [:]
        for (index, prompt) in prompts.enumerated() {
            let key: RunKey<Run> = prompt.run.map { .run($0) } ?? .alone(index)
            if byRun[key] == nil { keys.append(key) }
            var gathered = byRun[key] ?? (0, [])
            gathered.prompts.append(prompt.notes)
            gathered.end = max(gathered.end, prompt.end)
            byRun[key] = gathered
        }
        let currentKey = current.map { RunKey.run($0) }
        let ordered = keys.enumerated().sorted { lhs, rhs in
            let (left, right) = (lhs.element == currentKey, rhs.element == currentKey)
            if left != right { return right }
            return (byRun[lhs.element]?.end ?? 0, lhs.offset) < (byRun[rhs.element]?.end ?? 0, rhs.offset)
        }
        return ordered.map { (prompts: byRun[$0.element]?.prompts ?? [], isCurrent: $0.element == currentKey) }
    }

    private enum RunKey<Run: Hashable>: Hashable {
        case run(Run)
        /// A pass or voicing logged without a run.
        case alone(Int)
    }

    /// What its passes are played at: the level reached before this run.
    public func level(of subject: Subject) -> FadeLevel { passes.level(of: subject.lowest) }

    /// Where this run takes it.
    public func levelAfterRun(of subject: Subject) -> FadeLevel { passes.levelAfterRun(of: subject.lowest) }

    /// The run is over: what each subject's prompts are played at from now on is where the run took it.
    public mutating func endRun() {
        passes.endRun()
        voicings.endRun()
    }

    /// Counts the next pass of this run, given all that was logged of it.
    public mutating func add(_ notes: [Note]) {
        let results = notes.map(\.result)
        guard let first = notes.first, results.isComplete(size: first.size),
              Set(notes.map(\.place)) == Set(0..<max(0, first.size)) else { return }
        passes.count(first.subject.lowest, playedAt: first.level, isClean: results.isClean(size: first.size),
                     steps: first.steps)
    }

    /// What its voicings are played at: the level reached before this run.
    public func level(of shape: VoicingShape) -> FadeLevel { voicings.level(of: shape) }

    /// Where this run takes it.
    public func levelAfterRun(of shape: VoicingShape) -> FadeLevel { voicings.levelAfterRun(of: shape) }

    /// Counts the next voicing of this run, given all that was logged of it: played whole, or to where the time ran out. One skipped
    /// or cut short counts neither way.
    public mutating func add(voicing notes: [VoicingNote]) {
        guard let first = notes.first, let last = notes.last, notes.map(\.place) == Array(notes.indices),
              last.result.outcome == .timedOut || last.result.outcome == .answered && notes.count == first.shape.noteCount
        else { return }
        let isClean = notes.allSatisfy { $0.result.firstRight && !$0.result.hinted }
        voicings.count(first.shape, playedAt: first.level, isClean: isClean, steps: first.steps)
    }

    /// Counts passes of this run.
    mutating func add(_ passes: [PassResult], in tuning: Tuning) {
        for pass in passes { add(pass.attempts.compactMap { Note($0, in: tuning) }) }
    }
}

extension FadeLevels {
    /// One note of a logged pass, as far as fading goes.
    public struct Note: Hashable, Sendable {
        public let subject: Subject
        /// What the pass was played at.
        public let level: FadeLevel
        /// How many notes the whole pass has, and which this is (0 = first).
        public let size: Int
        public let place: Int
        let result: NoteResult
        /// The levels the pass moves between.
        let steps: [FadeLevel]

        /// `hinted`: whether a hint had been used in the pass by then.
        public init(subject: Subject, level: FadeLevel, hinted: Bool, size: Int, place: Int, outcome: Attempt.Outcome,
                    firstRight: Bool) {
            self.init(subject: subject, level: level, steps: FadeLevel.all, hinted: hinted, size: size, place: place,
                      outcome: outcome, firstRight: firstRight)
        }

        /// Logged before fade levels, at a stage: it moves between Shown, Faded and Hidden, as the stages did, so that
        /// no progress is lost.
        public init(subject: Subject, stage: FadeStage, hinted: Bool, size: Int, place: Int, outcome: Attempt.Outcome,
                    firstRight: Bool) {
            self.init(subject: subject, level: FadeLevel(stage), steps: FadeLevel.stageSteps, hinted: hinted, size: size,
                      place: place, outcome: outcome, firstRight: firstRight)
        }

        private init(subject: Subject, level: FadeLevel, steps: [FadeLevel], hinted: Bool, size: Int, place: Int,
                     outcome: Attempt.Outcome, firstRight: Bool) {
            self.subject = subject
            self.level = level
            self.steps = steps
            self.size = size
            self.place = place
            result = NoteResult(outcome: outcome, firstRight: firstRight, hinted: hinted)
        }

        /// Nil unless the attempt was in a pass.
        public init?(_ attempt: Attempt, in tuning: Tuning) {
            guard case .pass(let facts) = attempt.facts, let size = attempt.group?.size, let place = attempt.group?.place else { return nil }
            self.init(subject: Subject(tuning: tuning, scaleKind: facts.scale.kind, position: facts.position),
                      level: facts.fadeLevel, hinted: facts.hinted, size: size, place: place, outcome: attempt.outcome,
                      firstRight: attempt.firstRight)
        }
    }
}

extension FadeLevels.VoicingShape {
    fileprivate var noteCount: Int { stringSet.strings.count }
}

extension FadeLevels {
    /// One note of a logged voicing, as far as fading goes.
    public struct VoicingNote: Hashable, Sendable {
        public let shape: VoicingShape
        /// What the voicing was played at.
        public let level: FadeLevel
        /// Which of the voicing's notes it is (0 = lowest).
        public let place: Int
        let result: NoteResult
        /// The levels the voicing moves between.
        let steps: [FadeLevel]

        /// `hinted`: whether a hint had been used in the voicing by then.
        public init(shape: VoicingShape, level: FadeLevel, hinted: Bool, place: Int, outcome: Attempt.Outcome,
                    firstRight: Bool) {
            self.init(shape: shape, level: level, steps: FadeLevel.all, hinted: hinted, place: place, outcome: outcome,
                      firstRight: firstRight)
        }

        /// Logged before fade levels, at a stage: it moves between Shown, Faded and Hidden, as the stages did, so that
        /// no progress is lost.
        public init(shape: VoicingShape, stage: FadeStage, hinted: Bool, place: Int, outcome: Attempt.Outcome,
                    firstRight: Bool) {
            self.init(shape: shape, level: FadeLevel(stage), steps: FadeLevel.stageSteps, hinted: hinted, place: place,
                      outcome: outcome, firstRight: firstRight)
        }

        /// With its place in the group, which can be a climb: at a level, or logged before levels at a stage.
        public init?(shape: VoicingShape, level: FadeLevel?, stage: FadeStage?, hinted: Bool, groupPlace: Int,
                    outcome: Attempt.Outcome, firstRight: Bool) {
            let place = groupPlace % shape.noteCount
            if let level {
                self.init(shape: shape, level: level, hinted: hinted, place: place, outcome: outcome, firstRight: firstRight)
            } else if let stage {
                self.init(shape: shape, stage: stage, hinted: hinted, place: place, outcome: outcome, firstRight: firstRight)
            } else {
                return nil
            }
        }

        private init(shape: VoicingShape, level: FadeLevel, steps: [FadeLevel], hinted: Bool, place: Int,
                     outcome: Attempt.Outcome, firstRight: Bool) {
            self.shape = shape
            self.level = level
            self.steps = steps
            self.place = place
            result = NoteResult(outcome: outcome, firstRight: firstRight, hinted: hinted)
        }

        /// Nil unless the attempt was in a triad, with its level.
        public init?(_ attempt: Attempt, in tuning: Tuning) {
            guard case .triad(let facts) = attempt.facts, let level = facts.fadeLevel, let place = attempt.group?.place
            else { return nil }
            self.init(shape: VoicingShape(facts, in: tuning), level: level, stage: nil, hinted: facts.hinted,
                      groupPlace: place, outcome: attempt.outcome, firstRight: attempt.firstRight)
        }
    }
}
