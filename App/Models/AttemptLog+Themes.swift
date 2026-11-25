import Foundation
import PracticeCore
import SwiftData
import TheoryCore

/// Each day's theme.
extension AttemptLog {
    /// Whether a session that started on a date's day is saved. One with no attempts never is, so doesn't count.
    func hasStartedSession(on date: Date) -> Bool {
        let day = Calendar.practiceDay(of: date)
        return ((try? context.fetchCount(FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.day == day }))) ?? 0) > 0
    }

    /// The theme of a date's day, picked and saved the first time. One whose position or string set no longer does
    /// on the neck, or that has no string set yet, gets another, saved too.
    func theme(on date: Date, fretboard: Fretboard, system: Position.System) -> Theme {
        // With no saved theme to be read, one is picked but not saved, so that nothing is overwritten.
        guard let saved = try? savedTheme(on: date) else {
            return picker(on: date).theme(on: fretboard, system: system)
        }
        let picker = picker(on: date, rerolls: saved.first?.rerolls ?? 0)
        let old = saved.first?.theme
        let theme = old.map { picker.keepingKey(of: $0, on: fretboard, system: system) }
            ?? picker.theme(on: fretboard, system: system)
        if theme != old {
            if let record = saved.first {
                record.theme = theme
            } else {
                context.insert(DayTheme(day: Calendar.practiceDay(of: date), theme: theme))
            }
            save()
        }
        return theme
    }

    /// Replaces the theme of a date's day, unless a session has been started that day.
    func rerollTheme(on date: Date, fretboard: Fretboard, system: Position.System) {
        guard !hasStartedSession(on: date), let record = try? savedTheme(on: date).first else { return }
        record.rerolls += 1
        record.theme = picker(on: date, rerolls: record.rerolls).theme(on: fretboard, system: system, replacing: record.theme)
        save()
    }

    /// None or one.
    private func savedTheme(on date: Date) throws -> [DayTheme] {
        let day = Calendar.practiceDay(of: date)
        return try context.fetch(FetchDescriptor<DayTheme>(predicate: #Predicate { $0.day == day }))
    }

    private func picker(on date: Date, rerolls: Int = 0) -> ThemePicker {
        let day = Calendar.practiceDay(of: date)
        let past = (try? context.fetch(FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.day < day }))) ?? []
        return ThemePicker(day: day, seed: UInt64(Calendar.dayNumber(of: date)), rerolls: rerolls,
                           history: past.map { PastTheme(day: $0.day, theme: $0.theme) })
    }
}
