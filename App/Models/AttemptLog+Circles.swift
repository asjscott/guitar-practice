import Foundation
import PracticeCore
import SwiftData
import TheoryCore

extension AttemptLog {
    /// A circle drill's circles, oldest first, each from the attempts that share a circle id; on one tuning and capo when
    /// a fretboard is given. Complete or not (`CircleResult.isComplete`): the Hear → find it unlock reads the last
    /// complete Note circles' wrong notes.
    func circles(of kind: DrillKind, on fretboard: Fretboard? = nil) -> [CircleResult] {
        let id = kind.id
        let inCircles = #Predicate<LoggedAttempt> { $0.drill == id && $0.circleID != nil }
        let attempts = (try? context.fetch(FetchDescriptor(predicate: inCircles, sortBy: [SortDescriptor(\.date)]))) ?? []
        let tuning = fretboard?.tuning.openPitches.map(\.midi)
        var order: [UUID] = []
        var parts: [UUID: [CircleResult.Part]] = [:]
        var groups: [UUID: Int] = [:]
        for attempt in attempts {
            guard let circle = attempt.circleID, let outcome = attempt.outcome else { continue }
            if let fretboard, attempt.tuning != tuning || attempt.capo != fretboard.capo { continue }
            if parts[circle] == nil { order.append(circle) }
            var group = -1
            if let groupID = attempt.groupID {
                group = groups[groupID] ?? groups.count
                groups[groupID] = group
            }
            parts[circle, default: []].append(CircleResult.Part(
                group: group, groupSize: attempt.groupSize, outcome: outcome,
                responseTime: attempt.responseSeconds.map { .seconds($0) }, wrongNotes: attempt.wrongAnswers.count))
        }
        return order.map { CircleResult(parts: parts[$0] ?? []) }
    }

    /// The best circle of a circle drill so far on this tuning and capo; nil before there is a clean one.
    func circleBest(of kind: DrillKind, on fretboard: Fretboard) -> CircleResult? {
        CircleResult.best(of: circles(of: kind, on: fretboard))
    }
}
