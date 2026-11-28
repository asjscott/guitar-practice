#if DEBUG
import AppKit
import ListenCore
import PracticeCore
import SwiftData
import TheoryCore

/// Checks that what is logged survives a relaunch, when `GP_LOG_CHECK=<store file>` is set (see `scripts/log-check`).
///
/// `GP_LOG_CHECK_STEP=write` runs drills against a new store there; `read`, in a second process, prints what it
/// holds. `writeV1`, `writeV2` and `writeV3` instead make a store with an older schema, and `readAll` prints all that one holds
/// as the current one. It never opens the player's own log, and shows no window.
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
                switch step {
                case "writeV1": try writeV1(at: url)
                case "writeV2": try writeV2(at: url)
                case "writeV3": try writeV3(at: url)
                default: break
                }
                if step?.hasPrefix("writeV") == true { _exit(EXIT_SUCCESS) }
                let log = try AttemptLog.stored(at: url)
                if step == "read" {
                    try read(log)
                } else if step == "readAll" {
                    try readAll(log)
                } else {
                    try checkSessions()
                    try checkThemes()
                    try checkFreePractice()
                    try checkNoteCircle()
                    try checkScaleCircle()
                    try checkResume()
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
        let theme = Theme(key: .major(.bFlat), position: Position.ID(system: .caged, number: 3), stringSet: .eAD)
        let session = newSession()
        session.theme = theme
        session.themeProgression = "I–V–vi–IV"
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
                             startDegree: Scale.Degree(5, -1), tempo: 72, signature: TimeSignature(beats: 7, unit: 8) ?? .fourFour, fadeLevel: FadeLevel(2),
                             hinted: true, clickOffset: .milliseconds(-125), inputDelay: .microseconds(12500))
        let triad = TriadFacts(triad: Triad(.minor, root: .bFlat), inversion: .second, stringSet: .dGB)
        for (place, facts) in [AttemptFacts.pass(pass), .triad(triad)].enumerated() {
            let attempt = Attempt(prompt: NotePrompt(name: .f, string: 2, target: target), outcome: .skipped,
                                  group: AttemptGroup(number: place, size: 3, place: place), facts: facts)
            let record = LoggedAttempt(attempt, in: newDrill(), date: .now, source: .freePractice, groupID: UUID(),
                                       blockIndex: nil)
            log.context.insert(record)
        }

        // A time through's chords: one played as another voicing, one missed.
        let timeThrough = UUID()
        let played = VoicingRecord(notes: [.init(string: 2, fret: 2), .init(string: 3, fret: 0), .init(string: 4, fret: 0)])
        let accepted = [VoicingRecord(notes: [.init(string: 3, fret: 2), .init(string: 4, fret: 0), .init(string: 5, fret: 0)]),
                        VoicingRecord(notes: [.init(string: 1, fret: 2), .init(string: 2, fret: 2), .init(string: 3, fret: 0)])]
        for (place, played) in [played, nil].enumerated() {
            let chord = LoggedAttempt(date: .now, sourceRaw: AttemptSource.freePractice.rawValue, drill: "nearestVoicing",
                                      tuning: Tuning.standard.openPitches.map(\.midi), capo: 0, targetName: "E",
                                      targetPitchClass: 4, targetString: 2, targetFret: nil, targetPitch: nil,
                                      outcomeRaw: Attempt.Outcome.answered.rawValue, firstRight: false, responseSeconds: nil,
                                      wrongAnswers: [], groupID: timeThrough, blockIndex: nil)
            (chord.groupSize, chord.groupPlace) = (4, place + 2)
            (chord.progression, chord.keyTonic, chord.keyMode, chord.numeral) = ("I–V–vi–IV", 7, "major", "vi")
            (chord.chordRootName, chord.chordRoot, chord.chordQuality) = ("E", 4, "minor")
            (chord.positionSystem, chord.positionNumber, chord.positionOctave) = ("caged", 4, 0)
            (chord.playedVoicing, chord.acceptedVoicings) = (played, accepted)
            (chord.backingStyle, chord.tempo, chord.beatsPerBar, chord.beatUnit) = ("rock", 70, 4, 4)
            (chord.fadeLevel, chord.hinted) = (FadeLevel.last.number, place == 1)
            chord.chordOutcomeRaw = played == nil ? "missed" : "wrong"
            chord.firstOnsetSeconds = played.map { _ in -0.25 }
            chord.inputDelaySeconds = 0
            log.context.insert(chord)
        }

        // Nearest voicing at 60 BPM: G clean on D-G-B, D with a wrong note, Em missed.
        var progressionSetup = DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1)
        progressionSetup.options.key = .major(.g)
        progressionSetup.options.progression = Progression.named("I–V–vi–IV")
        progressionSetup.options.backing = BackingSettings(tempo: 60)
        var chords = DrillKind.nearestVoicing.makeDrill(progressionSetup)
        let chordRun = log.run()
        chords.handle(.start(at: .zero))
        for (pitch, onset) in [(55, 3.75), (59, 4.25), (62, 4.75), (54, 8.0), (58, 8.5)] {
            chords.handle(.played(Pitch(pitch), onset: .seconds(onset), at: .seconds(onset)))
        }
        chords.handle(.tick(at: .seconds(16.5)))
        chordRun.update(from: chords)

        // Chords in position: G clean, without backing, so its style and tempo are nil.
        var inPosition = DrillKind.chordsInPosition.makeDrill(progressionSetup)
        let inPositionRun = log.run()
        inPosition.handle(.start(at: .zero))
        for index in 1...3 {
            guard let target = inPosition.prompt?.target else { break }
            let onset = Duration.seconds(index)
            inPosition.handle(.played(inPosition.fretboard.pitch(at: target), onset: onset, at: onset))
        }
        inPositionRun.update(from: inPosition)

        // Two clean passes and one cut short by a pause, so the next is played at level 2.
        var passes = DrillKind.upAndDown.makeDrill(DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1))
        let passRun = log.run()
        passes.handle(.start(at: .zero))
        func playPass(_ notes: Int = .max) {
            for _ in 0..<min(notes, passes.display?.pass?.notes.count ?? 0) {
                guard let target = passes.prompt?.target, let start = passes.promptStart else { return }
                let onset = start + .milliseconds(500)
                passes.handle(.played(passes.fretboard.pitch(at: target), onset: onset, at: onset))
                passRun.update(from: passes)
            }
        }
        playPass()
        passes.handle(.skip(at: .seconds(100)))
        playPass()
        passes.handle(.skip(at: .seconds(200)))
        playPass(3)
        passes.handle(.pause(at: .seconds(300)))
        passes.handle(.resume(at: .seconds(400)))
        playPass(3)

        // A clean voicing, so that its shape is at level 1, then one with only its first note.
        var triadSetup = DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1)
        triadSetup.options.stringSets = [.dGB]
        var triads = DrillKind.triadPlayIt.makeDrill(triadSetup)
        let triadRun = log.run()
        triads.handle(.start(at: .zero))
        for index in 0..<4 {
            let onset = Duration.seconds(index + 1)
            triads.handle(.tick(at: onset))
            let next = triads.attempts.count % 3
            guard let location = triads.display?.markers[next].location else { break }
            triads.handle(.played(triads.fretboard.pitch(at: location), onset: onset, at: onset))
            triadRun.update(from: triads)
        }

        var other = theme
        other.stringSet = .gBE
        let dayTheme = DayTheme(day: "2026-07-25", theme: other, rerolls: 2)
        dayTheme.progression = "vi–IV–I–V"
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

    /// Sessions run by the Session screen's model, the daily routine without sound: one with attempts in its first block
    /// is saved with them, with no budget, and one with none isn't. In memory, since what is prompted varies by day.
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
        session.skip()
        // Step 2 has a planned length; the Note circle hasn't.
        session.extend()
        session.next()
        session.next()
        session.extend()
        session.extend()
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
              saved.map({ Array($0.blocks.map(\.extends).prefix(2)) }) == [[0, 2], [0, 0]],
              saved.allSatisfy({ $0.budgetMinutes == nil && $0.blocks.count == 8 }),
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

    /// A Note circle logs one attempt per location, a group per key and one circle id per run; the log reads circles
    /// back, complete or not, and the best clean one per tuning and capo. In memory.
    private static func checkNoteCircle() throws {
        func require(_ condition: Bool, _ what: String) throws {
            if !condition { throw LogCheckError.freePractice("Note circle: " + what) }
        }
        let log = AttemptLog.inMemory()
        let drill = DrillViewModel()
        drill.kind = .noteCircle
        drill.keepOptionsForSnapshot()
        drill.log = log
        for interval in [2.0, 1.0] {
            drill.start(seed: 1)
            drill.playCircleForSnapshot(every: .seconds(interval))
            drill.stop()
        }
        drill.start(seed: 1)
        drill.playCircleForSnapshot(5)
        drill.stop()
        let attempts = try log.context.fetch(FetchDescriptor<LoggedAttempt>())
        let locations = (attempts.count - 5) / 2
        try require(attempts.allSatisfy { $0.drill == "noteCircle" && $0.groupSize != nil }, "attempts")
        try require(Set(attempts.compactMap(\.circleID)).count == 3, "one circle id per run")
        try require(Set(attempts.compactMap(\.groupID)).count == 25, "a group per key")
        let circles = log.circles(of: .noteCircle)
        try require(circles.map(\.isComplete) == [true, true, false], "complete circles")
        try require(circles.map(\.time) == [.seconds(2 * locations), .seconds(locations), .seconds(5)], "times")
        try require(log.circleBest(of: .noteCircle, on: drill.fretboard) == circles[1], "the best")
        try require(log.circleBest(of: .noteCircle, on: Fretboard(tuning: .standard, capo: 2)) == nil, "best per capo")
    }

    /// A Scale circle logs its passes one way each, taking turns from up, with no tempo, and one circle id per run; a
    /// clean run moves the fade levels of the positions it went through, and the log reads its circle back. In memory.
    private static func checkScaleCircle() throws {
        func require(_ condition: Bool, _ what: String) throws {
            if !condition { throw LogCheckError.freePractice("Scale circle: " + what) }
        }
        let log = AttemptLog.inMemory()
        let drill = DrillViewModel()
        drill.kind = .scaleCircle
        drill.keepOptionsForSnapshot()
        drill.options.key = .major(.e)
        drill.options.position = Position.ID(system: .caged, number: CAGEDShape.c.number)
        drill.log = log
        drill.start(seed: 1)
        drill.playCircleForSnapshot()
        drill.stop()
        let attempts = try log.context.fetch(FetchDescriptor<LoggedAttempt>(sortBy: [SortDescriptor(\.date)]))
        try require(attempts.allSatisfy { $0.drill == "scaleCircle" && $0.tempo == nil && $0.groupSize != nil }, "attempts")
        try require(Set(attempts.compactMap(\.circleID)).count == 1, "one circle id")
        var directions: [String] = []
        for attempt in attempts where attempt.groupPlace == 0 { directions.append(attempt.passDirection ?? "-") }
        try require(directions == (0..<6).flatMap { _ in ["up", "down"] }, "directions")
        try require(log.circles(of: .scaleCircle).map(\.isClean) == [true], "the circle")
        let levels = log.fadeLevels(in: drill.setup.scaleCirclePositions.map(\.id), on: [])
        let theme = FadeLevels.Subject(tuning: drill.fretboard.tuning, scaleKind: .major,
                                       position: Position.ID(system: .caged, number: CAGEDShape.c.number))
        try require(levels.level(of: theme) > .first, "fade levels")
    }

    /// Resuming a scale drill takes up the tempo and the fade level that a session has moved meanwhile. In memory.
    private static func checkResume() throws {
        let suite = "LogCheck-\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite) else { throw LogCheckError.freePractice("no defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let log = AttemptLog.inMemory()
        let drill = DrillViewModel()
        drill.log = log
        drill.kind = .upAndDown
        drill.metronome = Metronome(output: AppSoundOutput(isInert: true), defaults: defaults)
        drill.start(seed: 1)
        drill.pause()

        defaults.set(76, forKey: MetronomeSettings.Key.tempo(of: .upAndDown))
        defaults.set(1, forKey: MetronomeSettings.Key.notClean(of: .upAndDown))
        var other = DrillKind.upAndDown.makeDrill(DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1))
        let run = log.run()
        other.handle(.start(at: .zero))
        // Six clean passes reach the last level, which shows only the roots.
        for _ in 0..<6 {
            for _ in 0..<(other.display?.pass?.notes.count ?? 0) {
                guard let target = other.prompt?.target, let start = other.promptStart else { break }
                other.handle(.played(other.fretboard.pitch(at: target), onset: start, at: start))
                run.update(from: other)
            }
            if let end = other.passEnd { other.handle(.tick(at: end)) }
        }

        drill.resume()
        guard drill.passSettings.tempo == 76, defaults.integer(forKey: MetronomeSettings.Key.tempo(of: .upAndDown)) == 76 else {
            throw LogCheckError.freePractice("resumed at \(drill.passSettings.tempo) BPM")
        }
        guard drill.passSettings.ladder.notClean == 1, defaults.integer(forKey: MetronomeSettings.Key.notClean(of: .upAndDown)) == 1 else {
            throw LogCheckError.freePractice("resumed with the old ladder count")
        }
        guard let markers = drill.snapshot.display?.markers, !markers.isEmpty, markers.allSatisfy(\.isAnswer) else {
            throw LogCheckError.freePractice("resumed at the old fade level")
        }
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
        try require(first?.theme.stringSet != nil && rerolled?.theme.stringSet != nil
                    && rerolled?.theme.stringSet != first?.theme.stringSet, "the string set rerolled")

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

        // Saved before themes had a string set.
        let record = try themes().first
        record?.stringSet = nil
        session.showTheme(on: evening)
        let given = session.theme
        try require(given?.key == rerolled?.key && given?.theme.position == rerolled?.theme.position, "the rest is kept")
        try require(given?.theme.stringSet != nil && record?.theme == given?.theme, "a theme without a string set gets one")
        // With the capo at 12 in Drop D, E-A-D has no voicing of C major's G.
        let before = record?.theme
        record?.theme = Theme(key: .major(.c), position: Position.ID(system: .caged, number: 3), stringSet: .eAD)
        session.tuning = TuningPreset.dropD.tuning
        session.capo = 12
        session.showTheme(on: evening)
        try require(session.theme?.key == .major(.c) && session.theme?.theme.stringSet != .eAD
                    && record?.theme == session.theme?.theme, "a disqualified string set is picked again")
        session.tuning = .standard
        session.capo = 0
        record?.theme = rerolled?.theme
        session.showTheme(on: evening)
        try require(before == given?.theme && session.theme == rerolled, "back to the first tuning")
        // Saved before themes had a progression.
        record?.progression = nil
        session.showTheme(on: evening)
        try require(session.theme?.theme.progression != nil && record?.progression == session.theme?.theme.progression?.id,
                    "a theme without a progression gets one")
        try require(session.theme?.theme.stringSet == rerolled?.theme.stringSet && session.theme?.key == rerolled?.key,
                    "and keeps the rest")
        record?.theme = rerolled?.theme
        session.showTheme(on: evening)

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

    /// A store as version 2 of the app left it: on top of version 1's, string sets, groups, passes and triads.
    private static func writeV2(at url: URL) throws {
        let schema = Schema(versionedSchema: PracticeSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        func id(_ number: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))! }
        func date(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: seconds) }

        let session = PracticeSchemaV2.Session(
            day: "2026-11-20", startedAt: date(3000), budgetMinutes: 20, naturalsOnly: false, wholeNeck: true,
            blocks: [SessionBlockRecord(drill: "upAndDown", plannedSeconds: 300, extends: 1, spentSeconds: 400),
                     SessionBlockRecord(drill: "triadPlayIt", plannedSeconds: 300, spentSeconds: 310.5)])
        session.id = id(3)
        session.endedAt = date(3800)
        session.stateRaw = "completed"
        session.totalSeconds = 800.25
        (session.themeTonic, session.themeMode, session.themePositionSystem) = (9, "minor", "caged")
        (session.themePositionNumber, session.themePositionOctave, session.themeStringSet) = (2, 0, "gBE")
        context.insert(session)

        func attempt(_ number: Int, drill: String, outcome: String, wrong: [WrongAnswerRecord] = [], group: Int,
                     place: Int) -> PracticeSchemaV2.Attempt {
            let record = PracticeSchemaV2.Attempt(
                date: date(Double(number)), sourceRaw: "session", drill: drill, tuning: [40, 45, 50, 55, 59, 64], capo: 0,
                targetName: "C", targetPitchClass: 0, targetString: 4, targetFret: 1, targetPitch: 60, outcomeRaw: outcome,
                firstRight: wrong.isEmpty, responseSeconds: 0.75, wrongAnswers: wrong, groupID: id(group), blockIndex: place)
            record.id = id(number)
            (record.groupSize, record.groupPlace) = (6, place)
            context.insert(record)
            record.session = session
            return record
        }
        let pass = attempt(21, drill: "upAndDown", outcome: "answered", wrong: [WrongAnswerRecord(pitch: 61)], group: 201, place: 0)
        (pass.scaleKind, pass.scaleTonic, pass.positionSystem, pass.positionNumber, pass.positionOctave) = ("minorPentatonic", 9, "caged", 2, 0)
        (pass.startDegree, pass.startDegreeAlteration, pass.tempo, pass.beatsPerBar, pass.beatUnit) = (3, -1, 80, 4, 4)
        (pass.fadeStageRaw, pass.hinted, pass.clickOffsetSeconds) = ("shown", false, 0.03125)
        let triad = attempt(22, drill: "triadPlayIt", outcome: "skipped", group: 202, place: 1)
        (triad.chordRootName, triad.chordRoot, triad.chordQuality, triad.inversion, triad.stringSet) = ("A", 9, "minor", "root", "gBE")
        (triad.fadeStageRaw, triad.hinted) = ("faded", true)

        let theme = PracticeSchemaV2.DayTheme(day: "2026-11-20", rerolls: 1, tonic: 9, mode: "minor", positionSystem: "caged",
                                              positionNumber: 2, positionOctave: 0)
        theme.stringSet = "gBE"
        context.insert(theme)
        try context.save()
    }

    /// A store as version 3 of the app left it: on top of version 2's, a pass at each fade stage, a progression's
    /// chord and the input delay.
    private static func writeV3(at url: URL) throws {
        let schema = Schema(versionedSchema: PracticeSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        func id(_ number: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))! }
        func date(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: seconds) }

        let session = PracticeSchemaV3.Session(
            day: "2026-11-24", startedAt: date(4000), budgetMinutes: 25, naturalsOnly: true, wholeNeck: false,
            blocks: [SessionBlockRecord(drill: "upAndDown", plannedSeconds: 600, spentSeconds: 610)])
        session.id = id(4)
        session.endedAt = date(4700)
        session.stateRaw = "completed"
        session.totalSeconds = 700.5
        (session.themeTonic, session.themeMode, session.themePositionSystem) = (7, "major", "caged")
        (session.themePositionNumber, session.themePositionOctave, session.themeStringSet) = (4, 0, "dGB")
        session.themeProgression = "I–V–vi–IV"
        context.insert(session)

        func attempt(_ number: Int, drill: String, group: Int, place: Int, size: Int) -> PracticeSchemaV3.Attempt {
            let record = PracticeSchemaV3.Attempt(
                date: date(Double(number)), sourceRaw: "session", drill: drill, tuning: [40, 45, 50, 55, 59, 64], capo: 0,
                targetName: "G", targetPitchClass: 7, targetString: 0, targetFret: 3, targetPitch: 43, outcomeRaw: "answered",
                firstRight: true, responseSeconds: 0.5, wrongAnswers: [], groupID: id(group), blockIndex: 0)
            record.id = id(number)
            (record.groupSize, record.groupPlace) = (size, place)
            context.insert(record)
            record.session = session
            return record
        }
        for (index, stage) in ["shown", "faded", "hidden"].enumerated() {
            let pass = attempt(31 + index, drill: "upAndDown", group: 301 + index, place: 0, size: 1)
            (pass.scaleKind, pass.scaleTonic, pass.positionSystem, pass.positionNumber, pass.positionOctave) = ("major", 7, "caged", 4, 0)
            (pass.startDegree, pass.startDegreeAlteration, pass.tempo, pass.beatsPerBar, pass.beatUnit) = (1, 0, 64, 4, 4)
            (pass.fadeStageRaw, pass.hinted, pass.clickOffsetSeconds, pass.inputDelaySeconds) = (stage, false, -0.0625, 0.0125)
        }
        let chord = attempt(34, drill: "stayInPosition", group: 304, place: 1, size: 4)
        (chord.progression, chord.keyTonic, chord.keyMode, chord.numeral) = ("I–V–vi–IV", 7, "major", "V")
        (chord.chordRootName, chord.chordRoot, chord.chordQuality) = ("D", 2, "major")
        (chord.positionSystem, chord.positionNumber, chord.positionOctave) = ("caged", 4, 0)
        chord.playedVoicing = VoicingRecord(notes: [.init(string: 2, fret: 0), .init(string: 3, fret: 2), .init(string: 4, fret: 3)])
        (chord.backingStyle, chord.tempo, chord.beatsPerBar, chord.beatUnit) = ("pop", 90, 4, 4)
        (chord.fadeStageRaw, chord.hinted, chord.chordOutcomeRaw, chord.firstOnsetSeconds) = ("faded", false, "clean", 0.125)
        chord.inputDelaySeconds = 0.0125

        let theme = PracticeSchemaV3.DayTheme(day: "2026-11-24", rerolls: 0, tonic: 7, mode: "major", positionSystem: "caged",
                                              positionNumber: 4, positionOctave: 0)
        (theme.stringSet, theme.progression) = ("dGB", "I–V–vi–IV")
        context.insert(theme)
        try context.save()
    }

    /// Everything saved, one line a record.
    private static func readAll(_ log: AttemptLog) throws {
        func text<T>(_ value: T?) -> String { value.map { "\($0)" } ?? "-" }
        func number(_ id: UUID?) -> String { id.map { String($0.uuidString.suffix(3)) } ?? "-" }
        func seconds(_ date: Date?) -> String { text(date?.timeIntervalSinceReferenceDate) }
        for session in try log.context.fetch(FetchDescriptor<PracticeSession>(sortBy: [SortDescriptor(\.startedAt)])) {
            print("session", number(session.id), session.day, seconds(session.startedAt), seconds(session.endedAt), session.stateRaw,
                  text(session.totalSeconds), text(session.budgetMinutes), session.naturalsOnly, session.wholeNeck,
                  "theme", text(session.themeTonic), text(session.themeMode), text(session.themePositionSystem),
                  text(session.themePositionNumber), text(session.themePositionOctave), text(session.themeStringSet),
                  text(session.themeProgression),
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
                  theme.positionOctave, text(theme.stringSet), text(theme.progression))
        }
    }

    /// An attempt's fields for groups, passes, triads and chords, those that are set.
    private static func newFields(of attempt: LoggedAttempt) -> String {
        let fields: [(String, Any?)] = [
            ("size", attempt.groupSize), ("place", attempt.groupPlace), ("scale", attempt.scaleKind),
            ("tonic", attempt.scaleTonic), ("system", attempt.positionSystem), ("number", attempt.positionNumber),
            ("octave", attempt.positionOctave), ("degree", attempt.startDegree),
            ("alteration", attempt.startDegreeAlteration), ("tempo", attempt.tempo), ("beats", attempt.beatsPerBar),
            ("unit", attempt.beatUnit), ("fade", attempt.fadeStageRaw), ("level", attempt.fadeLevel),
            ("as", attempt.playedFadeLevel?.number), ("hinted", attempt.hinted), ("circle", attempt.circleID.map { String($0.uuidString.suffix(3)) }),
            ("direction", attempt.passDirection),
            ("offset", attempt.clickOffsetSeconds), ("root", attempt.chordRootName), ("rootClass", attempt.chordRoot),
            ("quality", attempt.chordQuality), ("inversion", attempt.inversion), ("set", attempt.stringSet),
            ("delay", attempt.inputDelaySeconds), ("progression", attempt.progression), ("key", attempt.keyTonic),
            ("mode", attempt.keyMode), ("numeral", attempt.numeral), ("played", attempt.playedVoicing.map(text)),
            ("accepted", attempt.acceptedVoicings.map { $0.map(text).joined(separator: " ") }),
            ("style", attempt.backingStyle), ("chord", attempt.chordOutcomeRaw), ("onset", attempt.firstOnsetSeconds),
        ]
        let set = fields.compactMap { name, value in value.map { "\(name) \($0)" } }
        return "facts [\(set.joined(separator: ", "))]"
    }

    /// "2:2/3:0/4:0": the string and fret of each note, low to high.
    private static func text(_ voicing: VoicingRecord) -> String {
        voicing.notes.map { "\($0.string):\($0.fret)" }.joined(separator: "/")
    }

    private static func read(_ log: AttemptLog) throws {
        let eShape = FadeLevels.Subject(tuning: .standard, scaleKind: .major, position: Position.ID(system: .caged, number: 1))
        let levels = log.fadeLevels(in: [eShape.position], on: [.dGB])
        var dropD = eShape
        dropD.tuning = TuningPreset.dropD.tuning
        print("fade \(levels.level(of: eShape)), in Drop D \(levels.level(of: dropD))")
        let shapes = Triad.Quality.allCases.flatMap { quality in
            Triad.Inversion.allCases.map {
                FadeLevels.VoicingShape(tuning: .standard, quality: quality, inversion: $0, stringSet: .dGB)
            }
        }
        let shapeLevels = shapes.map { levels.level(of: $0).number }
        print("triads on D-G-B at level 1 \(shapeLevels.filter { $0 == 1 }.count), above \(shapeLevels.filter { $0 > 1 }.count)")
        var groups: [UUID] = []
        func group(of attempt: LoggedAttempt) -> String {
            guard let id = attempt.groupID else { return "none" }
            if !groups.contains(id) { groups.append(id) }
            return "\(groups.firstIndex(of: id) ?? -1)"
        }
        for attempt in try log.context.fetch(FetchDescriptor<LoggedAttempt>(sortBy: [SortDescriptor(\.date)])) {
            if [DrillKind.upAndDown.id, DrillKind.triadPlayIt.id].contains(attempt.drill) { continue }
            let wrong = attempt.wrongAnswers.map { $0.name ?? $0.pitch.map(String.init) ?? "?" }.joined(separator: ",")
            let target = "string \(attempt.targetString) fret \(attempt.targetFret ?? -1) pitch \(attempt.targetPitch ?? -1)"
            let time = attempt.responseSeconds == nil ? "no time" : "timed"
            let session = attempt.session.map { "\($0.day) block \(attempt.blockIndex ?? -1)" } ?? "none"
            print("attempt \(attempt.drill) \(attempt.sourceRaw) \(attempt.outcomeRaw) tuning \(attempt.tuning) capo \(attempt.capo)",
                  "target \(attempt.targetName) \(target) group \(group(of: attempt)) first \(attempt.firstRight) wrong [\(wrong)] \(time) session \(session) \(newFields(of: attempt))")
        }
        for session in try log.context.fetch(FetchDescriptor<PracticeSession>()) {
            print("session \(session.day) \(session.stateRaw) theme \(session.theme?.key.description ?? "none") set \(session.theme?.stringSet?.name ?? "none") progression \(session.themeProgression ?? "none")",
                  "blocks \(session.blocks.map(\.plannedSeconds)) attempts \(session.attempts.count)")
        }
        for theme in try log.context.fetch(FetchDescriptor<DayTheme>()) {
            print("theme \(theme.day) \(theme.theme?.key.description ?? "none") position \(theme.positionSystem) \(theme.positionNumber) rerolls \(theme.rerolls) set \(theme.theme?.stringSet?.name ?? "none") progression \(theme.progression ?? "none")")
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
