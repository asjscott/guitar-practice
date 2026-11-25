import Foundation
import PracticeCore
import SwiftData
import TheoryCore

extension AttemptLog {
    /// The fade stages reached in these positions, worked out from every pass logged in them. What can't be read is
    /// left out.
    func fadeStages(in positions: [Position.ID]) -> FadeStages {
        guard !positions.isEmpty else { return FadeStages() }
        // Only these positions' notes, since fetching every pass ever logged would hold up the start of a run.
        let systems = positions.map(\.system.rawValue), numbers = positions.map(\.number)
        let inPasses = #Predicate<LoggedAttempt> { attempt in
            (attempt.positionSystem.flatMap { systems.contains($0) } ?? false)
                && (attempt.positionNumber.flatMap { numbers.contains($0) } ?? false)
        }
        let notes = FetchDescriptor<LoggedAttempt>(predicate: inPasses, sortBy: [SortDescriptor(\.date)])
        let attempts = (try? context.fetch(notes)) ?? []
        return FadeStages(log: attempts.compactMap { attempt -> (group: UUID, note: FadeStages.Note)? in
            guard let group = attempt.groupID, let note = FadeStages.Note(attempt) else { return nil }
            return (group, note)
        })
    }
}

extension FadeStages.Note {
    /// Nil unless the attempt was in a pass, or if what is saved is unusable.
    fileprivate init?(_ attempt: LoggedAttempt) {
        guard let kind = attempt.scaleKind.flatMap(Scale.Kind.init), let number = attempt.positionNumber,
              let system = attempt.positionSystem.flatMap(Position.System.init),
              let stage = attempt.fadeStageRaw.flatMap(FadeStage.init), let size = attempt.groupSize,
              let place = attempt.groupPlace, let outcome = attempt.outcome, !attempt.tuning.isEmpty else { return nil }
        let subject = FadeStages.Subject(tuning: Tuning(attempt.tuning.map { Pitch($0) }), scaleKind: kind,
                                         position: Position.ID(system: system, number: number))
        self.init(subject: subject, stage: stage, hinted: attempt.hinted ?? false, size: size, place: place,
                  outcome: outcome, firstRight: attempt.firstRight)
    }
}
