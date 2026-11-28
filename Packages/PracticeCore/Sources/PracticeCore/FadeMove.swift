import TheoryCore

/// A fade level that moved: a scale kind in a position, or a shape of triad voicing, from one level to another. For the
/// routine session's summary.
public struct FadeMove: Hashable, Sendable {
    public enum Subject: Hashable, Sendable {
        case pass(FadeLevels.Subject)
        case voicing(FadeLevels.VoicingShape)
    }

    public let subject: Subject
    public let from: FadeLevel
    public let to: FadeLevel

    public init(subject: Subject, from: FadeLevel, to: FadeLevel) {
        self.subject = subject
        self.from = from
        self.to = to
    }

    /// "A shape, major: 1 → 3", "Root position on D-G-B, major: 2 → 3".
    public var text: String {
        let name = switch subject {
        case .pass(let subject): "\(subject.position.name(in: subject.tuning)), \(subject.scaleKind.name)"
        case .voicing(let shape): "\(shape.inversion.name) on \(shape.stringSet.name), \(shape.quality.rawValue)"
        }
        return "\(name): \(from.number) → \(to.number)"
    }
}

extension FadeLevels {
    /// What moved since `before`, each counting its run: positions first, up the shapes (or patterns) then by scale kind; then triad voicings,
    /// by string set, then quality, then inversion.
    public func moves(since before: FadeLevels) -> [FadeMove] {
        let passMoves = passes.subjects.union(before.passes.subjects)
            .sorted { $0.order.lexicographicallyPrecedes($1.order) }
            .compactMap { subject in
                FadeMove(.pass(subject), from: before.passes.levelAfterRun(of: subject), to: passes.levelAfterRun(of: subject))
            }
        let voicingMoves = voicings.subjects.union(before.voicings.subjects)
            .sorted { $0.order.lexicographicallyPrecedes($1.order) }
            .compactMap { shape in
                FadeMove(.voicing(shape), from: before.voicings.levelAfterRun(of: shape), to: voicings.levelAfterRun(of: shape))
            }
        return passMoves + voicingMoves
    }
}

extension FadeMove {
    /// Nil when it didn't move.
    fileprivate init?(_ subject: Subject, from: FadeLevel, to: FadeLevel) {
        guard from != to else { return nil }
        self.init(subject: subject, from: from, to: to)
    }
}

extension FadeLevels.Subject {
    fileprivate var order: [Int] {
        [Position.System.allCases.firstIndex(of: position.system) ?? 0, position.number,
         Scale.Kind.allCases.firstIndex(of: scaleKind) ?? 0] + tuning.openPitches.map(\.midi)
    }
}

extension FadeLevels.VoicingShape {
    fileprivate var order: [Int] {
        [StringSet.allCases.firstIndex(of: stringSet) ?? 0, Triad.Quality.allCases.firstIndex(of: quality) ?? 0,
         Triad.Inversion.allCases.firstIndex(of: inversion) ?? 0] + tuning.openPitches.map(\.midi)
    }
}
