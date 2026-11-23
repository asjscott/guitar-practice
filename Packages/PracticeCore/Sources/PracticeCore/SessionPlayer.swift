import TheoryCore

/// Where a session is.
public enum SessionStage: Hashable, Sendable {
    /// Before Start.
    case idle
    /// The current block's Ready card.
    case ready
    /// The current block's drill is running.
    case playing
    /// After the last block, or ended early.
    case finished
}

/// Something that happens to a session, with its time on the session's clock (the drills' too).
public enum SessionEvent: Hashable, Sendable {
    case start(at: Duration)
    /// Space: starts the block from its Ready card; while playing, ends the block.
    case next(at: Duration)
    /// Ends the session before its last block is over.
    case end(at: Duration)
    /// The clock moved on.
    case tick(at: Duration)

    // What the app does with sounds, so that they are never taken for answers.
    case soundStarted(AppSound, at: Duration, latency: Duration)
    case tonesStopped(at: Duration)

    // For the drill: ignored unless a block is playing.
    case played(Pitch, onset: Duration, at: Duration)
    case typed(NoteName, at: Duration)
    case skip(at: Duration)
    case `repeat`(at: Duration)
}

/// Runs a session's blocks: a pure state machine driven by events and a clock, like the drills it drives.
///
/// A block ends only when the player moves on. The open prompt is then dropped, unrecorded.
public struct SessionPlayer: Sendable {
    /// How long a Ready card waits before its block starts by itself.
    public static let readyTime: Duration = .seconds(5)

    public let blocks: [SessionBlock]
    public private(set) var stage: SessionStage = .idle

    /// The current block; while finished, the last one reached.
    public private(set) var blockIndex = 0

    /// The current block's drill: nil on its Ready card. Kept, stopped, once the session is finished.
    public private(set) var drill: (any Drill)?

    /// From Start, Ready cards and overtime included, up to the last event.
    public private(set) var elapsed: Duration = .zero

    /// What is left of the Ready card; nil unless one is up.
    public private(set) var readyRemaining: Duration?

    /// Ended before its last block was over.
    public private(set) var endedEarly = false

    private let setup: DrillSetup
    private var progress: [Progress]
    private var soundFilter = AppSoundFilter()
    private var lastEvent: Duration = .zero

    /// A block as played.
    private struct Progress: Sendable {
        /// Nil until it starts.
        var spent: Duration?
        var attempts: [Attempt] = []
    }

    /// Every block's drill gets `setup`, with a seed of its own.
    public init(blocks: [SessionBlock], setup: DrillSetup) {
        self.blocks = blocks
        self.setup = setup
        progress = blocks.map { _ in Progress() }
    }

    // MARK: - State

    /// The block time spent, overtime included; nil if the block hasn't started.
    public func spent(inBlock index: Int) -> Duration? { progress[index].spent }

    /// Until the block's planned end; negative in overtime.
    public func timeLeft(inBlock index: Int) -> Duration { blocks[index].length - (progress[index].spent ?? .zero) }

    /// The block's attempts, oldest first.
    public func attempts(inBlock index: Int) -> [Attempt] { progress[index].attempts }

    /// What has been done so far.
    public var summary: SessionSummary {
        SessionSummary(totalTime: elapsed, blocks: zip(blocks, progress).compactMap { block, progress in
            progress.spent.map {
                SessionSummary.Block(kind: block.kind, time: $0, stats: RunStats(attempts: progress.attempts))
            }
        })
    }

    /// The sounds the drill asked for since the last call: call it after every event, as for a drill.
    public mutating func takeSounds() -> [DrillSoundRequest] { drill?.takeSounds() ?? [] }

    // MARK: - Events

    public mutating func handle(_ event: SessionEvent) {
        switch event {
        case .start(let now):
            guard stage == .idle else { return }
            lastEvent = now
            showReady(0)
        case .next(let now):
            passTime(to: now)
            switch stage {
            case .ready: startBlock(at: now)
            case .playing: endBlock(at: now)
            case .idle, .finished: break
            }
        case .end(let now):
            guard stage == .ready || stage == .playing else { return }
            passTime(to: now)
            drill?.handle(.stop(at: now))
            endedEarly = true
            finish()
        case .tick(let now):
            passTime(to: now)
            if let readyRemaining, readyRemaining <= .zero { startBlock(at: now) } else { send(.tick(at: now)) }
        case .soundStarted(let sound, let now, let latency):
            soundFilter.started(sound, at: now, latency: latency)
        case .tonesStopped(let now):
            soundFilter.tonesStopped(at: now)
        case .played(let pitch, let onset, let now):
            passTime(to: now)
            if !soundFilter.ignores(onset: onset) { send(.played(pitch, onset: onset, at: now)) }
        case .typed(let name, let now):
            passTime(to: now)
            send(.typed(name, at: now))
        case .skip(let now):
            passTime(to: now)
            send(.skip(at: now))
        case .repeat(let now):
            passTime(to: now)
            send(.repeat(at: now))
        }
    }

    /// The only place time is counted. A played note can be handled after a later tick, so time never goes back.
    private mutating func passTime(to now: Duration) {
        let passed = max(.zero, now - lastEvent)
        lastEvent = max(lastEvent, now)
        switch stage {
        case .idle, .finished:
            return
        case .ready:
            readyRemaining = readyRemaining.map { max(.zero, $0 - passed) }
        case .playing:
            progress[blockIndex].spent? += passed
        }
        elapsed += passed
    }

    private mutating func showReady(_ index: Int) {
        drill = nil
        guard blocks.indices.contains(index) else { return finish() }
        blockIndex = index
        stage = .ready
        readyRemaining = Self.readyTime
    }

    private mutating func startBlock(at now: Duration) {
        stage = .playing
        readyRemaining = nil
        progress[blockIndex].spent = .zero
        var blockSetup = setup
        blockSetup.seed &+= UInt64(blockIndex)
        drill = blocks[blockIndex].kind.makeDrill(blockSetup)
        send(.start(at: now))
    }

    private mutating func endBlock(at now: Duration) {
        drill?.handle(.stop(at: now))
        if blockIndex + 1 < blocks.count { showReady(blockIndex + 1) } else { finish() }
    }

    private mutating func finish() {
        stage = .finished
        readyRemaining = nil
    }

    private mutating func send(_ event: DrillEvent) {
        guard stage == .playing, drill != nil else { return }
        drill?.handle(event)
        progress[blockIndex].attempts = drill?.attempts ?? []
    }
}
