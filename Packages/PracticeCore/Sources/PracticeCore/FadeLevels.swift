import TheoryCore

/// The fade level each subject has reached, worked out from the log and never stored (ADR 0007): from 0, one up for a
/// clean prompt and one down for any other. A prompt played at another level than the one reached doesn't count.
/// Each drill that fades keeps one per kind of subject, and decides what makes a prompt complete and clean.
public struct FadeLadder<Subject: Hashable & Sendable>: Hashable, Sendable {
    private var levels: [Subject: FadeLevel] = [:]

    public init() {}

    public func level(of subject: Subject) -> FadeLevel { levels[subject] ?? .first }

    /// Every subject counted so far; any other is at the first level.
    var subjects: Dictionary<Subject, FadeLevel>.Keys { levels.keys }

    /// Counts a complete prompt. `steps` are the levels it moves between: all of them, unless it was logged at a fade
    /// stage (`FadeLevel.stageSteps`).
    public mutating func count(_ subject: Subject, playedAt played: FadeLevel, isClean: Bool,
                               steps: [FadeLevel] = FadeLevel.all) {
        let reached = level(of: subject)
        guard played == reached else { return }
        levels[subject] = isClean ? steps.first { $0 > reached } ?? reached : steps.last { $0 < reached } ?? .first
    }
}

extension FadeLevel {
    /// The levels the old fade stages moved between: Shown, Faded and Hidden.
    public static let stageSteps = FadeStage.allCases.map(FadeLevel.init)
}

/// The fade levels reached in the scale and triad drills, from the logged passes and voicings: each scale kind in
/// each position, and each shape of triad voicing, voicing by voicing. Passes that aren't complete don't count.
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

    /// From logged notes, oldest first, each with its group: a pass's, and those of triads' voicings. A climb's voicings
    /// share a group, and a voicing that was started again is a new one.
    public init<Group: Hashable>(log: [(group: Group, note: Note)], voicings: [(group: Group, note: VoicingNote)] = []) {
        var groups: [Group] = []
        var passes: [Group: [Note]] = [:]
        for (group, note) in log {
            if passes[group] == nil { groups.append(group) }
            passes[group, default: []].append(note)
        }
        for group in groups { add(passes[group] ?? []) }

        var voicing: [VoicingNote] = []
        var voicingGroup: Group?
        for (group, note) in voicings {
            if note.place == 0 || group != voicingGroup {
                add(voicing: voicing)
                voicing = []
                voicingGroup = group
            }
            voicing.append(note)
        }
        add(voicing: voicing)
    }

    public func level(of subject: Subject) -> FadeLevel { passes.level(of: subject.lowest) }

    /// Counts the next pass, given all that was logged of it.
    public mutating func add(_ notes: [Note]) {
        let results = notes.map(\.result)
        guard let first = notes.first, results.isComplete(size: first.size),
              Set(notes.map(\.place)) == Set(0..<max(0, first.size)) else { return }
        passes.count(first.subject.lowest, playedAt: first.level, isClean: results.isClean(size: first.size),
                     steps: first.steps)
    }

    public func level(of shape: VoicingShape) -> FadeLevel { voicings.level(of: shape) }

    /// Counts the next voicing, given all that was logged of it: played whole, or to where the time ran out. One skipped
    /// or cut short counts neither way.
    public mutating func add(voicing notes: [VoicingNote]) {
        guard let first = notes.first, let last = notes.last, notes.map(\.place) == Array(notes.indices),
              last.result.outcome == .timedOut || last.result.outcome == .answered && notes.count == first.shape.noteCount
        else { return }
        let isClean = notes.allSatisfy { $0.result.firstRight && !$0.result.hinted }
        voicings.count(first.shape, playedAt: first.level, isClean: isClean, steps: first.steps)
    }

    /// Counts a run's passes.
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
