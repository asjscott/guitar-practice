import TheoryCore

/// The fade stage each scale kind has reached in each position, worked out from the logged passes and never stored:
/// from Shown, one on for a clean pass and one back for any other. Passes that aren't complete, or were played at a
/// stage other than the one reached, don't count. The same for each shape of triad voicing, voicing by voicing.
public struct FadeStages: Hashable, Sendable {
    /// What a stage belongs to, whatever the key, capo and octave.
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

    /// What a triad's stage belongs to, whatever its root, frets and capo.
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

    private var stages: [Subject: FadeStage] = [:]
    private var voicingStages: [VoicingShape: FadeStage] = [:]

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

    public func stage(of subject: Subject) -> FadeStage { stages[subject.lowest] ?? .shown }

    /// Counts the next pass, given all that was logged of it.
    public mutating func add(_ notes: [Note]) {
        let results = notes.map(\.result)
        guard let first = notes.first, results.isComplete(size: first.size),
              Set(notes.map(\.place)) == Set(0..<max(0, first.size)) else { return }
        let reached = stage(of: first.subject)
        guard first.stage == reached else { return }
        stages[first.subject.lowest] = results.isClean(size: first.size) ? reached.next : reached.previous
    }

    public func stage(of shape: VoicingShape) -> FadeStage { voicingStages[shape] ?? .shown }

    /// Counts the next voicing, given all that was logged of it: played whole, or to where the time ran out. One skipped
    /// or cut short counts neither way.
    public mutating func add(voicing notes: [VoicingNote]) {
        guard let first = notes.first, let last = notes.last, notes.map(\.place) == Array(notes.indices),
              last.result.outcome == .timedOut || last.result.outcome == .answered && notes.count == first.shape.noteCount
        else { return }
        let reached = stage(of: first.shape)
        guard first.stage == reached else { return }
        let isClean = notes.allSatisfy { $0.result.firstRight && !$0.result.hinted }
        voicingStages[first.shape] = isClean ? reached.next : reached.previous
    }

    /// Counts a run's passes.
    mutating func add(_ passes: [PassResult], in tuning: Tuning) {
        for pass in passes { add(pass.attempts.compactMap { Note($0, in: tuning) }) }
    }
}

extension FadeStages {
    /// One note of a logged pass, as far as fading goes.
    public struct Note: Hashable, Sendable {
        public let subject: Subject
        /// What the pass was played at.
        public let stage: FadeStage
        /// How many notes the whole pass has, and which this is (0 = first).
        public let size: Int
        public let place: Int
        let result: NoteResult

        /// `hinted`: whether a hint had been used in the pass by then.
        public init(subject: Subject, stage: FadeStage, hinted: Bool, size: Int, place: Int, outcome: Attempt.Outcome,
                    firstRight: Bool) {
            self.subject = subject
            self.stage = stage
            self.size = size
            self.place = place
            result = NoteResult(outcome: outcome, firstRight: firstRight, hinted: hinted)
        }

        /// Nil unless the attempt was in a pass.
        public init?(_ attempt: Attempt, in tuning: Tuning) {
            guard case .pass(let facts) = attempt.facts, let size = attempt.group?.size, let place = attempt.group?.place else { return nil }
            self.init(subject: Subject(tuning: tuning, scaleKind: facts.scale.kind, position: facts.position),
                      stage: facts.fadeStage, hinted: facts.hinted, size: size, place: place, outcome: attempt.outcome,
                      firstRight: attempt.firstRight)
        }
    }
}

extension FadeStages.VoicingShape {
    fileprivate var noteCount: Int { stringSet.strings.count }
}

extension FadeStages {
    /// One note of a logged voicing, as far as fading goes.
    public struct VoicingNote: Hashable, Sendable {
        public let shape: VoicingShape
        /// What the voicing was played at.
        public let stage: FadeStage
        /// Which of the voicing's notes it is (0 = lowest).
        public let place: Int
        let result: NoteResult

        /// `hinted`: whether a hint had been used in the voicing by then.
        public init(shape: VoicingShape, stage: FadeStage, hinted: Bool, place: Int, outcome: Attempt.Outcome, firstRight: Bool) {
            self.shape = shape
            self.stage = stage
            self.place = place
            result = NoteResult(outcome: outcome, firstRight: firstRight, hinted: hinted)
        }

        /// With its place in the group, which can be a climb.
        public init(shape: VoicingShape, stage: FadeStage, hinted: Bool, groupPlace: Int, outcome: Attempt.Outcome,
                    firstRight: Bool) {
            self.init(shape: shape, stage: stage, hinted: hinted, place: groupPlace % shape.noteCount, outcome: outcome,
                      firstRight: firstRight)
        }

        /// Nil unless the attempt was in a triad, with its stage.
        public init?(_ attempt: Attempt, in tuning: Tuning) {
            guard case .triad(let facts) = attempt.facts, let stage = facts.fadeStage, let place = attempt.group?.place else { return nil }
            self.init(shape: VoicingShape(facts, in: tuning), stage: stage, hinted: facts.hinted, groupPlace: place,
                      outcome: attempt.outcome, firstRight: attempt.firstRight)
        }
    }
}

extension FadeStage {
    /// One on; Hidden stays.
    fileprivate var next: FadeStage { self == .shown ? .faded : .hidden }
    /// One back; Shown stays.
    fileprivate var previous: FadeStage { self == .hidden ? .faded : .shown }
}
