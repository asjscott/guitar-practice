import Foundation
import Observation
import PracticeCore
import SwiftData

/// What is saved: attempts as they happen, sessions and themes. One per process, in the environment.
///
/// Every change is saved at once. Nothing logged is deleted.
@MainActor @Observable
final class AttemptLog {
    let container: ModelContainer

    /// Why practice isn't being saved, for a notice; nil when it is.
    var problem: String? { openProblem ?? saveProblem }

    private let openProblem: String?
    private var saveProblem: String?

    /// Use it to fetch and insert sessions and themes, then call `save()`.
    var context: ModelContext { container.mainContext }

    private init(container: ModelContainer, problem: String? = nil) {
        self.container = container
        openProblem = problem
        container.mainContext.autosaveEnabled = false
        endCutOffSessions()
    }

    /// The player's own log, in a file of this app's. If it can't be opened it is left alone, and this run's
    /// attempts are kept only in memory. Xcode previews get an empty log in memory.
    static func live() -> AttemptLog {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return inMemory() }
        do {
            let folder = URL.applicationSupportDirectory.appending(path: "GuitarPractice", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return try AttemptLog(container: makeContainer(at: folder.appending(path: "Practice.store")))
        } catch {
            return inMemory(problem: error.localizedDescription)
        }
    }

    /// A log in a given file.
    static func stored(at url: URL) throws -> AttemptLog {
        try AttemptLog(container: makeContainer(at: url))
    }

    /// An empty log that is never written to disk: snapshots and previews.
    static func inMemory(problem: String? = nil) -> AttemptLog {
        do {
            return try AttemptLog(container: makeContainer(at: nil), problem: problem)
        } catch {
            fatalError("The practice schema is invalid: \(error)")
        }
    }

    private static func makeContainer(at url: URL?) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PracticeSchemaV4.self)
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: PracticeMigrationPlan.self, configurations: configuration)
    }

    /// A session still in progress when the log is opened was cut off by a quit or crash. Nothing is resumed.
    private func endCutOffSessions() {
        let inProgress = SessionState.inProgress.rawValue
        do {
            let cutOff = try context.fetch(FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.stateRaw == inProgress }))
            guard !cutOff.isEmpty else { return }
            for session in cutOff { session.state = .endedEarly }
            save()
        } catch {
            saveProblem = error.localizedDescription
        }
    }

    /// Saves everything inserted or changed. What can't be saved is kept and tried again next time.
    func save() {
        do {
            try context.save()
            saveProblem = nil
        } catch {
            saveProblem = error.localizedDescription
        }
    }

    /// Where one run's attempts go. A run in a session gives the session (saved with its first attempt) and the
    /// block's index; free practice gives neither.
    func run(session: PracticeSession? = nil, blockIndex: Int? = nil) -> RunLog {
        RunLog(log: self, session: session, blockIndex: blockIndex)
    }
}

/// Logs one run of one drill, from its start.
@MainActor
final class RunLog {
    private let log: AttemptLog
    private let session: PracticeSession?
    private let blockIndex: Int?
    private var count = 0
    private var groupIDs: [Int: UUID] = [:]
    private var circleIDs: [Int: UUID] = [:]

    fileprivate init(log: AttemptLog, session: PracticeSession?, blockIndex: Int?) {
        self.log = log
        self.session = session
        self.blockIndex = blockIndex
    }

    /// Saves the drill's attempts that ended since the last call: call it after every event.
    func update(from drill: any Drill) {
        let new = drill.attemptsToLog.dropFirst(count)
        guard !new.isEmpty else { return }
        for attempt in new {
            let record = LoggedAttempt(attempt, in: drill, date: .now, source: session == nil ? .freePractice : .session,
                                       groupID: (attempt.group?.number).map(groupID),
                                       circleID: (attempt.group?.circle).map(circleID), blockIndex: blockIndex)
            log.context.insert(record)
            record.session = session
        }
        count += new.count
        log.save()
    }

    private func groupID(_ group: Int) -> UUID {
        if let id = groupIDs[group] { return id }
        let id = UUID()
        groupIDs[group] = id
        return id
    }

    /// One per circle of fifths in the run (`AttemptGroup.circle`).
    private func circleID(_ circle: Int) -> UUID {
        if let id = circleIDs[circle] { return id }
        let id = UUID()
        circleIDs[circle] = id
        return id
    }
}
