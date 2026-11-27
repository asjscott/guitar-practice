import Foundation
import PracticeCore
import SwiftData

extension AttemptLog {
    /// How long each completed daily-routine session took, Free time left out, oldest first. Sessions with a budget
    /// (before the routine) don't count.
    func routineTimes() -> [Duration] {
        let completed = SessionState.completed.rawValue
        let descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.stateRaw == completed && $0.budgetMinutes == nil && $0.totalSeconds != nil },
            sortBy: [SortDescriptor(\.startedAt)])
        let sessions = (try? context.fetch(descriptor)) ?? []
        return sessions.map { session in
            let freeTime = session.blocks.filter { $0.drill == DrillKind.freeTime.id }.compactMap(\.spentSeconds)
                .reduce(0, +)
            return .seconds(max(0, (session.totalSeconds ?? 0) - freeTime))
        }
    }
}
