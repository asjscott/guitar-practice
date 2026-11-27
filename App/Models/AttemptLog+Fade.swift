import Foundation
import PracticeCore
import SwiftData
import TheoryCore

extension AttemptLog {
    /// The fade levels reached in these positions, and by triads on these string sets, worked out from everything logged
    /// in them. What can't be read is left out.
    func fadeLevels(in positions: [Position.ID], on stringSets: Set<StringSet>) -> FadeLevels {
        FadeLevels(log: passNotes(in: positions), voicings: voicingNotes(on: stringSets))
    }

    private func passNotes(in positions: [Position.ID]) -> [(group: UUID, note: FadeLevels.Note)] {
        guard !positions.isEmpty else { return [] }
        // Only these positions' notes, since fetching every pass ever logged would hold up the start of a run.
        let systems = positions.map(\.system.rawValue), numbers = positions.map(\.number)
        let inPasses = #Predicate<LoggedAttempt> { attempt in
            (attempt.positionSystem.flatMap { systems.contains($0) } ?? false)
                && (attempt.positionNumber.flatMap { numbers.contains($0) } ?? false)
        }
        let notes = FetchDescriptor<LoggedAttempt>(predicate: inPasses, sortBy: [SortDescriptor(\.date)])
        let attempts = (try? context.fetch(notes)) ?? []
        return attempts.compactMap { attempt in
            guard let group = attempt.groupID, let note = FadeLevels.Note(attempt) else { return nil }
            return (group, note)
        }
    }

    private func voicingNotes(on stringSets: Set<StringSet>) -> [(group: UUID, note: FadeLevels.VoicingNote)] {
        guard !stringSets.isEmpty else { return [] }
        let sets = stringSets.map(\.rawValue)
        let onSets = #Predicate<LoggedAttempt> { attempt in attempt.stringSet.flatMap { sets.contains($0) } ?? false }
        let notes = FetchDescriptor<LoggedAttempt>(predicate: onSets, sortBy: [SortDescriptor(\.date)])
        let attempts = (try? context.fetch(notes)) ?? []
        return attempts.compactMap { attempt in
            guard let group = attempt.groupID, let note = FadeLevels.VoicingNote(attempt) else { return nil }
            return (group, note)
        }
    }
}

extension FadeLevels.Note {
    /// Nil unless the attempt was in a pass, or if what is saved is unusable.
    fileprivate init?(_ attempt: LoggedAttempt) {
        guard let kind = attempt.scaleKind.flatMap(Scale.Kind.init), let number = attempt.positionNumber,
              let system = attempt.positionSystem.flatMap(Position.System.init),
              let size = attempt.groupSize, let place = attempt.groupPlace, let outcome = attempt.outcome,
              !attempt.tuning.isEmpty else { return nil }
        let subject = FadeLevels.Subject(tuning: Tuning(attempt.tuning.map { Pitch($0) }), scaleKind: kind,
                                         position: Position.ID(system: system, number: number))
        let hinted = attempt.hinted ?? false
        if let level = attempt.fadeLevel {
            self.init(subject: subject, level: FadeLevel(level), hinted: hinted, size: size, place: place, outcome: outcome,
                      firstRight: attempt.firstRight)
        } else if let stage = attempt.fadeStageRaw.flatMap(FadeStage.init) {
            self.init(subject: subject, stage: stage, hinted: hinted, size: size, place: place, outcome: outcome,
                      firstRight: attempt.firstRight)
        } else {
            return nil
        }
    }
}

extension FadeLevels.VoicingNote {
    /// Nil unless the attempt was in a triad and saved its level, or before levels its stage, or if what is saved is
    /// unusable.
    fileprivate init?(_ attempt: LoggedAttempt) {
        guard let quality = attempt.chordQuality.flatMap(Triad.Quality.init), let set = attempt.stringSet.flatMap(StringSet.init),
              let inversion = attempt.inversion.flatMap(Triad.Inversion.init), let place = attempt.groupPlace,
              let outcome = attempt.outcome, !attempt.tuning.isEmpty else { return nil }
        let shape = FadeLevels.VoicingShape(tuning: Tuning(attempt.tuning.map { Pitch($0) }), quality: quality,
                                            inversion: inversion, stringSet: set)
        self.init(shape: shape, level: attempt.fadeLevel.map(FadeLevel.init),
                  stage: attempt.fadeStageRaw.flatMap(FadeStage.init), hinted: attempt.hinted ?? false, groupPlace: place,
                  outcome: outcome, firstRight: attempt.firstRight)
    }
}
