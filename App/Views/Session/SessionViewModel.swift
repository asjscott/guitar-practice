import Foundation
import Observation
import PracticeCore
import TheoryCore

/// The Session screen's state. Connects audio input, keys and the attempt log to the PracticeCore session player, and
/// turns the player's state into what the screen shows. It knows nothing of any particular drill.
///
/// The session's clock is the drill clock: host time, as in `DrillViewModel`.
@MainActor @Observable
final class SessionViewModel {
    /// What the view draws from the player, copied after each event and only replaced when it changes.
    struct Snapshot: Equatable {
        var stage: SessionStage = .idle
        var blockIndex = 0
        var blocks: [BlockProgress] = []
        /// Whole seconds left of the Ready card.
        var readySeconds = 0
        var display: DrillDisplay?
    }

    /// A block in the drills bar.
    struct BlockProgress: Equatable {
        var kind: DrillKind
        /// What is left, or for a block that is over, what was spent.
        var timeText: String
        /// Of the planned length, 0–1.
        var fraction: Double
    }

    /// The tuning and capo in Settings, for the next session. One that is going keeps its own.
    var tuning: Tuning = .standard
    var capo = 0

    /// The setup choices; the view keeps them.
    var setup = SessionSetup()

    /// Where attempts are saved; the view sets it before a session can start.
    @ObservationIgnored var log: AttemptLog?

    /// Plays the sounds a drill asks for; nil = silence. An empty list stops what is playing.
    @ObservationIgnored var playSounds: (([DrillSoundRequest]) -> Void)?

    private(set) var snapshot = Snapshot()

    /// The finished session's, until Done.
    private(set) var summary: SessionSummary?

    /// The neck the session was started on.
    private(set) var fretboard = Fretboard(tuning: .standard)

    /// Now on the session's clock, in host seconds; moves with each tick (drives the countdown ring).
    private(set) var now: Double = 0

    @ObservationIgnored private var player: SessionPlayer?
    @ObservationIgnored private var record: PracticeSession?
    @ObservationIgnored private var runLog: (blockIndex: Int, log: RunLog)?
    @ObservationIgnored private var lastPromptStart: Duration?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let feed = PlayedNoteFeed()

    private static let tickInterval: Duration = .milliseconds(33)

    var stage: SessionStage { snapshot.stage }

    /// From Start until it is finished.
    var isActive: Bool { stage == .ready || stage == .playing }

    // MARK: - Setup

    private func drillSetup(seed: UInt64) -> DrillSetup {
        let fretboard = Fretboard(tuning: tuning, capo: capo)
        return DrillSetup(fretboard: fretboard, options: setup.drillOptions(on: fretboard), seed: seed)
    }

    /// The blocks a session would have: every drill that has something to prompt.
    func plan(on date: Date = .now) -> [SessionBlock] {
        let drillSetup = drillSetup(seed: 0)
        let drills = DrillKind.all.filter { $0.makeDrill(drillSetup).nothingToPromptReason == nil }
        return SessionPlanner.plan(drills.map { WeightedDrill($0) }, budget: setup.budget, day: Calendar.dayNumber(of: date))
    }

    /// Why no drill can prompt anything; nil when one can.
    var nothingToPromptReason: String? {
        let drillSetup = drillSetup(seed: 0)
        let reasons = DrillKind.all.map { $0.makeDrill(drillSetup).nothingToPromptReason }
        return reasons.contains(nil) ? nil : reasons.compactMap { $0 }.first
    }

    // MARK: - Control

    func start(on date: Date = .now, seed: UInt64 = .random(in: .min ... .max)) {
        guard stage == .idle, nothingToPromptReason == nil else { return }
        let blocks = plan(on: date)
        let drillSetup = drillSetup(seed: seed)
        fretboard = drillSetup.fretboard
        player = SessionPlayer(blocks: blocks, setup: drillSetup)
        record = PracticeSession(
            day: Calendar.practiceDay(of: date), startedAt: date, budgetMinutes: setup.minutes,
            naturalsOnly: setup.notes == .naturals, wholeNeck: setup.range == .wholeNeck,
            blocks: blocks.map { SessionBlockRecord(drill: $0.kind.id, plannedSeconds: $0.length / .seconds(1)) })
        send(.start(at: clockNow()))
        startTicking()
    }

    /// Space.
    func next() { send(.next(at: clockNow())) }

    /// S.
    func skip() { send(.skip(at: clockNow())) }

    /// R: what it does is up to the drill.
    func repeatPrompt() { send(.repeat(at: clockNow())) }

    /// A note name, typed and submitted.
    func typed(_ name: NoteName) { send(.typed(name, at: clockNow())) }

    /// The screen is closing: a session that is going ends early.
    func leave() {
        send(.end(at: clockNow()))
        feed.reset()
    }

    /// Return on the summary: back to setup.
    func done() {
        guard stage == .finished else { return }
        player = nil
        record = nil
        runLog = nil
        summary = nil
        snapshot = Snapshot()
    }

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                guard let self, !Task.isCancelled else { return }
                send(.tick(at: clockNow()))
            }
        }
    }

    private func clockNow() -> Duration {
        let seconds = AudioInputService.hostTimeNow()
        now = seconds
        return .seconds(seconds)
    }

    // MARK: - The player

    private func send(_ event: SessionEvent) {
        guard var player, player.stage != .finished else { return }
        let stageBefore = player.stage
        player.handle(event)
        let sounds = player.takeSounds()
        self.player = player

        logAttempts(of: player)
        requestSounds(sounds, from: player)
        if player.stage != stageBefore { updateRecord(from: player) }
        if player.stage == .finished {
            ticker?.cancel()
            ticker = nil
            summary = player.summary
        }
        let new = Snapshot(of: player)
        if new != snapshot { snapshot = new }
    }

    private func logAttempts(of player: SessionPlayer) {
        guard let log, let record, let drill = player.drill else { return }
        if runLog?.blockIndex != player.blockIndex {
            runLog = (player.blockIndex, log.run(session: record, blockIndex: player.blockIndex))
        }
        runLog?.log.update(from: drill)
    }

    /// A new prompt, or none, also stops what is playing.
    private func requestSounds(_ sounds: [DrillSoundRequest], from player: SessionPlayer) {
        let promptStart = player.drill?.promptStart
        if promptStart != lastPromptStart || !sounds.isEmpty { playSounds?(sounds) }
        lastPromptStart = promptStart
    }

    /// Only a session with attempts has been inserted, and only then is there anything to save.
    private func updateRecord(from player: SessionPlayer) {
        guard let record else { return }
        record.blocks = record.blocks.enumerated().map { index, block in
            var block = block
            block.spentSeconds = player.spent(inBlock: index).map { $0 / .seconds(1) }
            return block
        }
        if player.stage == .finished {
            record.state = player.endedEarly ? .endedEarly : .completed
            record.endedAt = .now
            record.totalSeconds = player.elapsed / .seconds(1)
        }
        if record.modelContext != nil { log?.save() }
    }

    /// The prompt's time left, while it awaits an answer.
    var countdown: DrillCountdown? {
        let now = Duration.seconds(now)
        return player?.drill.flatMap { DrillCountdown(drill: $0, at: now) }
    }

    // MARK: - Listening

    /// The consumer for `.listensToAudioInput(_:)`.
    var audioConsumer: AudioInputConsumer {
        feed.consumer { [weak self] notes in self?.heard(notes) }
    }

    private func heard(_ notes: [HeardNote]) {
        for note in notes {
            send(.played(note.pitch, onset: .seconds(note.onset), at: .seconds(note.detected)))
        }
    }

    #if DEBUG
    /// Answers the current prompt, as if a right or wrong note had been played now (see `Snapshots`).
    func playForSnapshot(right: Bool) {
        guard let drill = player?.drill, let prompt = drill.prompt,
              let location = prompt.target ?? fretboard.locations(of: prompt.pitchClass, onString: prompt.string,
                                                                  frets: drill.options.frets).first else { return }
        let pitch = fretboard.pitch(at: location)
        let now = clockNow()
        send(.played(right ? pitch : pitch + Interval(1), onset: now, at: now))
    }
    #endif
}

extension SessionViewModel.Snapshot {
    @MainActor fileprivate init(of player: SessionPlayer) {
        stage = player.stage
        blockIndex = player.blockIndex
        readySeconds = player.readyRemaining.map { Int(($0 / .seconds(1)).rounded(.up)) } ?? 0
        display = player.drill?.display
        blocks = player.blocks.indices.map { index in
            let block = player.blocks[index]
            let spent = player.spent(inBlock: index)
            let isOver = spent != nil && index < player.blockIndex
            return .init(
                kind: block.kind,
                timeText: isOver ? clockText(spent ?? .zero) : clockText(player.timeLeft(inBlock: index), rounding: .up),
                // In 200ths, so that the bar moves smoothly without a redraw on every tick.
                fraction: isOver ? 1 : min(1, ((spent ?? .zero) / block.length * 200).rounded(.down) / 200))
        }
    }
}

extension Calendar {
    /// A count of local calendar days, one more each day.
    static func dayNumber(of date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.ordinality(of: .day, in: .era, for: date) ?? 0
    }
}
