#if DEBUG
import AppKit
import ListenCore
import PracticeCore
import SwiftData
import TheoryCore

/// Checks that what is logged survives a relaunch, when `GP_LOG_CHECK=<store file>` is set (see `scripts/log-check`).
///
/// `GP_LOG_CHECK_STEP=write` runs drills against a new store there; `read`, in a second process, prints what it
/// holds. `writeV1` instead makes a store with schema V1, and `readAll` prints all that one holds as V2. It never opens the player's own log, and shows no window.
@MainActor
enum LogCheck {
    private static let environment = ProcessInfo.processInfo.environment

    static var isRequested: Bool { environment["GP_LOG_CHECK"] != nil }

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task {
            do {
                let url = URL(fileURLWithPath: environment["GP_LOG_CHECK"] ?? "")
                let step = environment["GP_LOG_CHECK_STEP"]
                if step == "writeV1" {
                    try writeV1(at: url)
                    _exit(EXIT_SUCCESS)
                }
                let log = try AttemptLog.stored(at: url)
                if step == "read" {
                    try read(log)
                } else if step == "readAll" {
                    try readAll(log)
                } else {
                    try checkSessions()
                    try checkThemes()
                    try checkFreePractice()
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
        // Still in progress when this process dies, so ended early when the log is next opened.
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
        log.context.insert(LoggedAttempt(typed, in: newDrill(), date: .now, source: .freePractice, groupID: UUID(),
                                         blockIndex: nil))

        // Two sweeps: the attempts of each share a group ID.
        var sweeps = DrillKind.allInstances.makeDrill(DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1))
        let sweepRun = log.run()
        sweeps.handle(.start(at: .zero))
        for event in [DrillEvent.skip(at: .seconds(1)), .skip(at: .seconds(2)), .repeat(at: .seconds(3)), .skip(at: .seconds(4))] {
            sweeps.handle(event)
            sweepRun.update(from: sweeps)
        }

        // Passes and triads.
        let pass = PassFacts(scale: Scale(.blues, tonic: .a), position: Position.ID(system: .caged, number: 4, octave: 1),
                             startDegree: Scale.Degree(5, -1), tempo: 72, beatsPerBar: 7, beatUnit: 8, fadeStage: .faded,
                             hinted: true, clickOffset: .milliseconds(-125))
        let triad = TriadFacts(triad: Triad(.minor, root: .bFlat), inversion: .second, stringSet: .dGB)
        for (place, facts) in [AttemptFacts.pass(pass), .triad(triad)].enumerated() {
            let attempt = Attempt(prompt: NotePrompt(name: .f, string: 2, target: target), outcome: .skipped,
                                  group: AttemptGroup(number: place, size: 3, place: place), facts: facts)
            log.context.insert(LoggedAttempt(attempt, in: newDrill(), date: .now, source: .freePractice, groupID: UUID(),
                                             blockIndex: nil))
        }

        let dayTheme = DayTheme(day: "2026-07-25", theme: theme, rerolls: 2)
        dayTheme.stringSet = StringSet.gBE.rawValue
        session.themeStringSet = StringSet.eAD.rawValue
        log.context.insert(dayTheme)
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
        session.end()
        session.done()
        session.start()
        session.next()
        session.skip()
        session.extend()
        session.extend()
        session.skip()
        while session.isActive { session.next() }
        session.done()
        session.start()
        session.next()
        session.skip()
        session.pause()
        guard session.stage == .paused else { throw LogCheckError.sessions(["not paused"]) }
        session.skip()      // nothing happens while paused
        session.resume()
        session.leave()
        guard session.stage == .paused else { throw LogCheckError.sessions(["leaving didn't pause"]) }
        let noAccess = AudioInputState(permission: .undetermined, device: nil, devices: [], isRunning: false)
        session.inputChanged(noAccess)
        session.resume()
        guard session.stage == .paused else { throw LogCheckError.sessions(["resumed without access"]) }
        session.askToEnd()
        session.end()

        let saved = try log.context.fetch(FetchDescriptor<PracticeSession>(sortBy: [SortDescriptor(\.startedAt)]))
        let attempts = try log.context.fetch(FetchDescriptor<LoggedAttempt>())
        guard saved.map(\.attempts.count) == [2, 1], saved.map(\.state) == [.completed, .endedEarly],
              saved.allSatisfy({ $0.endedAt != nil && $0.totalSeconds != nil && $0.blocks.first?.spentSeconds != nil }),
              saved.map({ $0.blocks.first?.extends }) == [2, 0],
              attempts.count == 3, attempts.allSatisfy({ $0.source == .session && $0.blockIndex == 0 }) else {
            throw LogCheckError.sessions(saved.map { "\($0.stateRaw) \($0.attempts.count)" })
        }
    }

    /// Free practice pauses as a session does, and a paused run logs nothing. In memory.
    private static func checkFreePractice() throws {
        func require(_ condition: Bool, _ what: String) throws {
            if !condition { throw LogCheckError.freePractice(what) }
        }
        let interface = AudioInputDevice(uid: "a", name: "Interface", channelCount: 2)
        let ready = AudioInputState(permission: .granted, device: interface, devices: [interface], isRunning: true)
        var asked = ready
        asked.permission = .undetermined
        var denied = ready
        denied.permission = .denied
        var gone = ready
        gone.device = nil
        gone.devices = []

        let log = AttemptLog.inMemory()
        let drill = DrillViewModel()
        drill.log = log
        drill.inputChanged(asked)
        drill.start(seed: 1)
        try require(!drill.isRunning, "started without access")
        for lost in [denied, gone] {
            drill.inputChanged(ready)
            drill.start(seed: 1)
            if drill.isPaused { drill.resume() }
            try require(drill.isRunning && !drill.isPaused, "didn't go on")
            drill.inputChanged(lost)
            try require(drill.isPaused && drill.pauseNotice != nil, "losing the input didn't pause")
            drill.resume()
            try require(drill.isPaused, "resumed without an input")
        }
        drill.inputChanged(ready)
        drill.resume()
        drill.skip()
        drill.leave()
        try require(drill.isRunning && drill.isPaused, "leaving didn't pause")
        drill.skip()
        try require(drill.snapshot.attempts.count == 1, "the run survives leaving")
        try require(try log.context.fetchCount(FetchDescriptor<LoggedAttempt>()) == 1, "a paused run logs nothing")
        drill.resume()
        drill.pause(notice: "The Mac went to sleep.")
        try require(drill.isPaused, "sleep didn't pause")
        drill.stop()
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
        session.end()
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
        session.showTheme(on: midnight)
        session.reroll(on: midnight)
        try require(session.stage == .paused && session.theme == rerolled, "a session paused past midnight keeps its theme")
        session.end()
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

    /// A store as version 1 of the app left it: a session that ended, one cut off, sweeps, wrong answers, themes.
    private static func writeV1(at url: URL) throws {
        let schema = Schema(versionedSchema: PracticeSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        func id(_ number: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))! }
        func date(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: seconds) }

        let ended = PracticeSchemaV1.Session(
            day: "2026-07-25", startedAt: date(1000), budgetMinutes: 15, naturalsOnly: true, wholeNeck: false,
            blocks: [SessionBlockRecord(drill: "a", plannedSeconds: 450, extends: 2, spentSeconds: 460.5),
                     SessionBlockRecord(drill: "b", plannedSeconds: 450)])
        ended.id = id(1)
        ended.endedAt = date(1900)
        ended.stateRaw = "completed"
        ended.totalSeconds = 900.5
        (ended.themeTonic, ended.themeMode, ended.themePositionSystem) = (10, "major", "threeNotesPerString")
        (ended.themePositionNumber, ended.themePositionOctave) = (6, 1)
        let cutOff = PracticeSchemaV1.Session(day: "2026-07-26", startedAt: date(2000), budgetMinutes: 30, naturalsOnly: false,
                                              wholeNeck: true, blocks: [])
        cutOff.id = id(2)
        context.insert(ended)
        context.insert(cutOff)

        func attempt(_ number: Int, drill: String, outcome: String, fret: Int? = nil, pitch: Int? = nil, seconds: Double? = nil,
                     wrong: [WrongAnswerRecord] = [], sweep: Int? = nil, session: PracticeSchemaV1.Session? = nil, block: Int? = nil) {
            let record = PracticeSchemaV1.Attempt(
                date: date(Double(number)), sourceRaw: session == nil ? "freePractice" : "session", drill: drill,
                tuning: [38, 45, 50, 55, 59, 64], capo: 2, targetName: "B♭", targetPitchClass: 10, targetString: 2,
                targetFret: fret, targetPitch: pitch, outcomeRaw: outcome, firstRight: outcome == "answered" && wrong.isEmpty,
                responseSeconds: seconds, wrongAnswers: wrong, sweepID: sweep.map(id), blockIndex: block)
            record.id = id(number)
            context.insert(record)
            record.session = session
        }
        attempt(11, drill: "notePlayIt", outcome: "answered", fret: 8, pitch: 58, seconds: 1.25,
                wrong: [WrongAnswerRecord(pitch: 65), WrongAnswerRecord(name: "E♭")], session: ended, block: 1)
        attempt(12, drill: "allInstances", outcome: "answered", fret: 8, pitch: 58, seconds: 0.5, sweep: 101)
        attempt(13, drill: "allInstances", outcome: "timedOut", fret: 20, pitch: 70, sweep: 101)
        attempt(14, drill: "allInstances", outcome: "skipped", sweep: 102, session: cutOff, block: 0)

        for (day, rerolls) in [("2026-07-25", 2), ("2026-07-26", 0)] {
            context.insert(PracticeSchemaV1.DayTheme(day: day, rerolls: rerolls, tonic: 3, mode: "minor", positionSystem: "caged",
                                                     positionNumber: 3, positionOctave: 1))
        }
        try context.save()
    }

    /// Everything saved, one line a record.
    private static func readAll(_ log: AttemptLog) throws {
        func text<T>(_ value: T?) -> String { value.map { "\($0)" } ?? "-" }
        func number(_ id: UUID?) -> String { id.map { String($0.uuidString.suffix(3)) } ?? "-" }
        func seconds(_ date: Date?) -> String { text(date?.timeIntervalSinceReferenceDate) }
        for session in try log.context.fetch(FetchDescriptor<PracticeSession>(sortBy: [SortDescriptor(\.startedAt)])) {
            print("session", number(session.id), session.day, seconds(session.startedAt), seconds(session.endedAt), session.stateRaw,
                  text(session.totalSeconds), session.budgetMinutes, session.naturalsOnly, session.wholeNeck,
                  "theme", text(session.themeTonic), text(session.themeMode), text(session.themePositionSystem),
                  text(session.themePositionNumber), text(session.themePositionOctave), text(session.themeStringSet),
                  "attempts", session.attempts.map { number($0.id) }.sorted())
            for block in session.blocks {
                print("block", block.drill, block.plannedSeconds, block.extends, text(block.spentSeconds))
            }
        }
        for attempt in try log.context.fetch(FetchDescriptor<LoggedAttempt>(sortBy: [SortDescriptor(\.date)])) {
            print("attempt", number(attempt.id), seconds(attempt.date), attempt.sourceRaw, attempt.drill, attempt.tuning, attempt.capo)
            print("  target", attempt.targetName, attempt.targetPitchClass, attempt.targetString, text(attempt.targetFret),
                  text(attempt.targetPitch), attempt.outcomeRaw, attempt.firstRight, text(attempt.responseSeconds),
                  attempt.wrongAnswers.map { $0.name ?? text($0.pitch) })
            print("  group", number(attempt.groupID), "session", number(attempt.session?.id), text(attempt.blockIndex),
                  newFields(of: attempt))
        }
        for theme in try log.context.fetch(FetchDescriptor<DayTheme>(sortBy: [SortDescriptor(\.day)])) {
            print("theme", theme.day, theme.rerolls, theme.tonic, theme.mode, theme.positionSystem, theme.positionNumber,
                  theme.positionOctave, text(theme.stringSet))
        }
    }

    /// An attempt's fields for groups, passes and triads, those that are set.
    private static func newFields(of attempt: LoggedAttempt) -> String {
        let fields: [(String, Any?)] = [
            ("size", attempt.groupSize), ("place", attempt.groupPlace), ("scale", attempt.scaleKind),
            ("tonic", attempt.scaleTonic), ("system", attempt.positionSystem), ("number", attempt.positionNumber),
            ("octave", attempt.positionOctave), ("degree", attempt.startDegree),
            ("alteration", attempt.startDegreeAlteration), ("tempo", attempt.tempo), ("beats", attempt.beatsPerBar),
            ("unit", attempt.beatUnit), ("fade", attempt.fadeStageRaw), ("hinted", attempt.hinted),
            ("offset", attempt.clickOffsetSeconds), ("root", attempt.chordRootName), ("rootClass", attempt.chordRoot),
            ("quality", attempt.chordQuality), ("inversion", attempt.inversion), ("set", attempt.stringSet),
        ]
        let set = fields.compactMap { name, value in value.map { "\(name) \($0)" } }
        return "facts [\(set.joined(separator: ", "))]"
    }

    private static func read(_ log: AttemptLog) throws {
        var groups: [UUID] = []
        func group(of attempt: LoggedAttempt) -> String {
            guard let id = attempt.groupID else { return "none" }
            if !groups.contains(id) { groups.append(id) }
            return "\(groups.firstIndex(of: id) ?? -1)"
        }
        for attempt in try log.context.fetch(FetchDescriptor<LoggedAttempt>(sortBy: [SortDescriptor(\.date)])) {
            let wrong = attempt.wrongAnswers.map { $0.name ?? $0.pitch.map(String.init) ?? "?" }.joined(separator: ",")
            let target = "string \(attempt.targetString) fret \(attempt.targetFret ?? -1) pitch \(attempt.targetPitch ?? -1)"
            let time = attempt.responseSeconds == nil ? "no time" : "timed"
            let session = attempt.session.map { "\($0.day) block \(attempt.blockIndex ?? -1)" } ?? "none"
            print("attempt \(attempt.drill) \(attempt.sourceRaw) \(attempt.outcomeRaw) tuning \(attempt.tuning) capo \(attempt.capo)",
                  "target \(attempt.targetName) \(target) group \(group(of: attempt)) first \(attempt.firstRight) wrong [\(wrong)] \(time) session \(session) \(newFields(of: attempt))")
        }
        for session in try log.context.fetch(FetchDescriptor<PracticeSession>()) {
            print("session \(session.day) \(session.stateRaw) theme \(session.theme?.key.description ?? "none") set \(session.themeStringSet ?? "none")",
                  "blocks \(session.blocks.map(\.plannedSeconds)) attempts \(session.attempts.count)")
        }
        for theme in try log.context.fetch(FetchDescriptor<DayTheme>()) {
            print("theme \(theme.day) \(theme.theme?.key.description ?? "none") position \(theme.positionSystem) \(theme.positionNumber) rerolls \(theme.rerolls) set \(theme.stringSet ?? "none")")
        }
    }

    private enum LogCheckError: Error {
        case notSaved(String)
        case sessions([String])
        case theme(String)
        case freePractice(String)
    }
}
#endif
