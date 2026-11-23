#if DEBUG
import AppKit
import PracticeCore
import SwiftData
import TheoryCore

/// Checks that what is logged survives a relaunch, when `GP_LOG_CHECK=<store file>` is set (see `scripts/log-check`).
///
/// `GP_LOG_CHECK_STEP=write` runs drills against a new store there; `read`, in a second process, prints what it
/// holds. It never opens the player's own log, and shows no window.
@MainActor
enum LogCheck {
    private static let environment = ProcessInfo.processInfo.environment

    static var isRequested: Bool { environment["GP_LOG_CHECK"] != nil }

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task {
            do {
                let log = try AttemptLog.stored(at: URL(fileURLWithPath: environment["GP_LOG_CHECK"] ?? ""))
                if environment["GP_LOG_CHECK_STEP"] == "read" {
                    try read(log)
                } else {
                    try checkSessions()
                    try checkThemes()
                    try await write(log)
                }
                if let problem = log.problem { throw LogCheckError.notSaved(problem) }
                // As abrupt as a crash: nothing gets a chance to save on the way out.
                fflush(stdout)
                _exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data("Log check failed: \(error)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        app.run()
        exit(EXIT_FAILURE)
    }

    private static func write(_ log: AttemptLog) async throws {
        let drill = DrillViewModel()
        drill.log = log
        drill.tuning = TuningPreset.dropD.tuning
        drill.capo = 2

        // Logged: answered after a wrong note, skipped, timed out. The prompt cut off by a pause and the one cut off
        // by Stop are not.
        drill.start(seed: 1)
        drill.playForSnapshot(right: false)
        drill.playForSnapshot(right: true)
        drill.skip()
        drill.skip()
        try await Task.sleep(for: .milliseconds(10_400))
        drill.skip()
        drill.playForSnapshot(right: false)
        drill.togglePause()
        drill.togglePause()
        drill.playForSnapshot(right: false)
        drill.stop()

        // Never logged: a check run.
        drill.options.order = .inOrder
        drill.start(seed: 1)
        drill.playForSnapshot(right: true)
        drill.skip()
        drill.skip()
        drill.stop()

        // A session is saved with its first attempt, and one with none isn't.
        let theme = Theme(key: .major(.bFlat), position: Position.ID(system: .caged, number: 3))
        let session = newSession()
        session.theme = theme
        session.state = .endedEarly
        var sessionDrill = newDrill()
        let run = log.run(session: session, blockIndex: 1)
        sessionDrill.handle(.start(at: .zero))
        sessionDrill.handle(.skip(at: .seconds(1)))
        run.update(from: sessionDrill)
        run.update(from: sessionDrill)
        var unanswered = newDrill()
        unanswered.handle(.start(at: .zero))
        log.run(session: newSession(), blockIndex: 0).update(from: unanswered)

        // What Note → play it doesn't use: a typed wrong answer, a sweep and an exact target.
        let target = FretboardLocation(string: 2, fret: 3)
        let typed = Attempt(prompt: NotePrompt(name: .f, string: 2, target: target, sweep: 0), outcome: .answered,
                            responseTime: .milliseconds(1250), wrongAnswers: [.name(.bFlat)], location: target)
        log.context.insert(LoggedAttempt(typed, in: newDrill(), date: .now, source: .freePractice, sweepID: UUID(),
                                         blockIndex: nil))

        log.context.insert(DayTheme(day: "2026-07-25", theme: theme, rerolls: 2))
        log.save()
    }

    private static func newDrill() -> any Drill {
        DrillKind.notePlayIt.makeDrill(DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1))
    }

    private static func newSession() -> PracticeSession {
        PracticeSession(day: "2026-07-25", startedAt: .now, budgetMinutes: 15, naturalsOnly: true, wholeNeck: false,
                        blocks: [SessionBlockRecord(drill: "a", plannedSeconds: 450, spentSeconds: 460.5),
                                 SessionBlockRecord(drill: "b", plannedSeconds: 450)])
    }

    /// Sessions run by the Session screen's model, whatever drills there are: one with attempts in its first block is
    /// saved with them, and one with none isn't. In memory, since what is prompted varies by day.
    private static func checkSessions() throws {
        let log = AttemptLog.inMemory()
        let session = SessionViewModel()
        session.log = log
        session.start()
        session.next()
        session.leave()
        session.done()
        session.start()
        session.next()
        session.skip()
        session.skip()
        while session.isActive { session.next() }
        session.done()
        session.start()
        session.next()
        session.skip()
        session.leave()

        let saved = try log.context.fetch(FetchDescriptor<PracticeSession>(sortBy: [SortDescriptor(\.startedAt)]))
        let attempts = try log.context.fetch(FetchDescriptor<LoggedAttempt>())
        guard saved.map(\.attempts.count) == [2, 1], saved.map(\.state) == [.completed, .endedEarly],
              saved.allSatisfy({ $0.endedAt != nil && $0.totalSeconds != nil && $0.blocks.first?.spentSeconds != nil }),
              attempts.count == 3, attempts.allSatisfy({ $0.source == .session && $0.blockIndex == 0 }) else {
            throw LogCheckError.sessions(saved.map { "\($0.stateRaw) \($0.attempts.count)" })
        }
    }

    /// A day's theme through rerolls, a discarded session, a relaunch, a session past midnight, another position
    /// system and the next day. In memory.
    private static func checkThemes() throws {
        func require(_ condition: Bool, _ what: String) throws {
            if !condition { throw LogCheckError.theme(what) }
        }
        let log = AttemptLog.inMemory()
        func launch() -> SessionViewModel {
            let session = SessionViewModel()
            session.log = log
            return session
        }
        func themes() throws -> [DayTheme] { try log.context.fetch(FetchDescriptor<DayTheme>(sortBy: [SortDescriptor(\.day)])) }
        let evening = DateComponents(calendar: .current, year: 2026, month: 9, day: 30, hour: 23, minute: 50).date!
        let midnight = evening.addingTimeInterval(20 * 60)

        var session = launch()
        session.showTheme(on: evening)
        let first = session.theme
        try require(try themes().map(\.theme) == [first?.theme] && session.canReroll, "saved when first shown")
        session.start(on: evening)
        session.leave()
        session.done()
        session.showTheme(on: evening)
        try require(session.theme == first && session.canReroll, "a discarded session isn't a start")
        session.reroll(on: evening)
        let rerolled = session.theme
        try require(rerolled?.key != first?.key && rerolled?.positionName != first?.positionName, "rerolled")

        session = launch()
        session.showTheme(on: evening)
        try require(session.theme == rerolled && session.canReroll, "a reroll survives a relaunch")
        session.positionSystem = .threeNotesPerString
        session.showTheme(on: evening)
        try require(session.theme?.key == rerolled?.key && session.theme?.theme.position.system == .threeNotesPerString,
                    "another position system")
        session.positionSystem = .caged
        session.showTheme(on: evening)
        try require(session.theme == rerolled, "back to the first position system")

        session.start(on: evening)
        session.next()
        session.skip()
        session.showTheme(on: midnight)
        session.reroll(on: midnight)
        try require(session.theme == rerolled, "a session past midnight keeps its theme")
        session.leave()
        session.done()
        session.showTheme(on: evening)
        session.reroll(on: evening)
        try require(session.theme == rerolled && !session.canReroll, "no reroll after a start")
        session.showTheme(on: midnight)
        try require(session.theme?.key != rerolled?.key && session.theme?.positionName != rerolled?.positionName && session.canReroll,
                    "the next day's theme")
        let saved = try log.context.fetch(FetchDescriptor<PracticeSession>())
        try require(saved.map(\.theme) == [rerolled?.theme] && saved.map(\.day) == ["2026-09-30"], "saved with the session")
        try require(try themes().map(\.rerolls) == [1, 0], "one theme a day")
    }

    private static func read(_ log: AttemptLog) throws {
        for attempt in try log.context.fetch(FetchDescriptor<LoggedAttempt>(sortBy: [SortDescriptor(\.date)])) {
            let wrong = attempt.wrongAnswers.map { $0.name ?? $0.pitch.map(String.init) ?? "?" }.joined(separator: ",")
            let target = "string \(attempt.targetString) fret \(attempt.targetFret ?? -1) pitch \(attempt.targetPitch ?? -1)"
            let time = attempt.responseSeconds == nil ? "no time" : "timed"
            let session = attempt.session.map { "\($0.day) block \(attempt.blockIndex ?? -1)" } ?? "none"
            print("attempt \(attempt.drill) \(attempt.sourceRaw) \(attempt.outcomeRaw) tuning \(attempt.tuning) capo \(attempt.capo)",
                  "target \(attempt.targetName) \(target) sweep \(attempt.sweepID != nil) first \(attempt.firstTryRight) wrong [\(wrong)] \(time) session \(session)")
        }
        for session in try log.context.fetch(FetchDescriptor<PracticeSession>()) {
            print("session \(session.day) \(session.stateRaw) theme \(session.theme?.key.description ?? "none")",
                  "blocks \(session.blocks.map(\.plannedSeconds)) attempts \(session.attempts.count)")
        }
        for theme in try log.context.fetch(FetchDescriptor<DayTheme>()) {
            print("theme \(theme.day) \(theme.theme?.key.description ?? "none") position \(theme.positionSystem) \(theme.positionNumber) rerolls \(theme.rerolls)")
        }
    }

    private enum LogCheckError: Error {
        case notSaved(String)
        case sessions([String])
        case theme(String)
    }
}
#endif
