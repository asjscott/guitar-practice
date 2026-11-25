import TheoryCore

/// The fade stage each scale kind has reached in each position, worked out from the logged passes and never stored:
/// from Shown, one on for a clean pass and one back for any other. Passes that aren't complete, or were played at a
/// stage other than the one reached, don't count.
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

    private var stages: [Subject: FadeStage] = [:]

    public init() {}

    /// From logged notes, oldest first, each with its group.
    public init<Group: Hashable>(log: [(group: Group, note: Note)]) {
        var groups: [Group] = []
        var passes: [Group: [Note]] = [:]
        for (group, note) in log {
            if passes[group] == nil { groups.append(group) }
            passes[group, default: []].append(note)
        }
        for group in groups { add(passes[group] ?? []) }
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
        let result: PassNoteResult

        /// `hinted`: whether a hint had been used in the pass by then.
        public init(subject: Subject, stage: FadeStage, hinted: Bool, size: Int, place: Int, outcome: Attempt.Outcome,
                    firstRight: Bool) {
            self.subject = subject
            self.stage = stage
            self.size = size
            self.place = place
            result = PassNoteResult(outcome: outcome, firstRight: firstRight, hinted: hinted)
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

extension FadeStage {
    /// One on; Hidden stays.
    fileprivate var next: FadeStage { self == .shown ? .faded : .hidden }
    /// One back; Shown stays.
    fileprivate var previous: FadeStage { self == .hidden ? .faded : .shown }
}
