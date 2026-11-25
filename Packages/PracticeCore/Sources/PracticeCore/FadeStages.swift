import TheoryCore

/// One note of a logged pass, as far as fading goes.
public struct PassNote: Hashable, Sendable {
    public var subject: FadeStages.Subject
    /// What the pass was played at.
    public var stage: FadeStage
    /// Whether a hint had been used in the pass by then.
    public var hinted: Bool
    /// How many notes the whole pass has, and which this is (0 = first).
    public var size: Int
    public var place: Int
    public var outcome: Attempt.Outcome
    public var firstRight: Bool

    public init(subject: FadeStages.Subject, stage: FadeStage, hinted: Bool, size: Int, place: Int,
                outcome: Attempt.Outcome, firstRight: Bool) {
        self.subject = subject
        self.stage = stage
        self.hinted = hinted
        self.size = size
        self.place = place
        self.outcome = outcome
        self.firstRight = firstRight
    }

    /// Nil unless the attempt was in a pass.
    public init?(_ attempt: Attempt, in tuning: Tuning) {
        guard case .pass(let facts) = attempt.facts, let size = attempt.group?.size, let place = attempt.group?.place else { return nil }
        self.init(subject: FadeStages.Subject(tuning: tuning, scaleKind: facts.scale.kind, position: facts.position),
                  stage: facts.fadeStage, hinted: facts.hinted, size: size, place: place, outcome: attempt.outcome,
                  firstRight: attempt.firstRight)
    }
}

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
    public init<Group: Hashable>(log: [(group: Group, note: PassNote)]) {
        var groups: [Group] = []
        var passes: [Group: [PassNote]] = [:]
        for (group, note) in log {
            if passes[group] == nil { groups.append(group) }
            passes[group, default: []].append(note)
        }
        for group in groups { add(passes[group] ?? []) }
    }

    public func stage(of subject: Subject) -> FadeStage { stages[subject.lowest] ?? .shown }

    /// Counts the next pass, given all that was logged of it.
    public mutating func add(_ notes: [PassNote]) {
        guard let first = notes.first, notes.count == first.size, Set(notes.map(\.place)) == Set(0..<max(0, first.size)),
              !notes.contains(where: { $0.outcome == .skipped }) else { return }
        let reached = stage(of: first.subject)
        guard first.stage == reached else { return }
        let isClean = notes.allSatisfy { $0.firstRight && !$0.hinted }
        stages[first.subject.lowest] = isClean ? reached.next : reached.previous
    }

    /// Counts a run's passes.
    mutating func add(_ passes: [PassResult], in tuning: Tuning) {
        for pass in passes { add(pass.attempts.compactMap { PassNote($0, in: tuning) }) }
    }
}

extension FadeStage {
    /// One on; Hidden stays.
    fileprivate var next: FadeStage { self == .shown ? .faded : .hidden }
    /// One back; Shown stays.
    fileprivate var previous: FadeStage { self == .hidden ? .faded : .shown }
}
