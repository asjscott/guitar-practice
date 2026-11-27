import TheoryCore

/// Where a session is.
public enum SessionStage: Hashable, Sendable {
    /// Before Start.
    case idle
    /// The current block's Ready card.
    case ready
    /// The current block's drill is running.
    case playing
    /// Paused on a Ready card or in a drill: no time passes, and any prompt is hidden.
    case paused
    /// After the last block, or ended early.
    case finished
}

/// Something that happens to a session, with its time on the session's clock (the drills' too).
public enum SessionEvent: Hashable, Sendable {
    case start(at: Duration)
    /// Space: starts the block from its Ready card; while playing, ends the block.
    case next(at: Duration)
    case pause(at: Duration)
    /// Back to what was paused: a Ready card counts down afresh; a drill follows its own resume rule.
    /// Without sound, a block that needs it is left for the next one.
    case resume(at: Duration)
    /// +: moves the planned end of the block that is playing 2 minutes later, past it too.
    case extend(at: Duration)
    /// Ends the session: early, unless in a last block that only ends so (Free time).
    case end(at: Duration)
    /// The clock moved on.
    case tick(at: Duration)

    // What the app does with sounds, so that they are never taken for answers.
    case soundStarted(AppSound, at: Duration, latency: Duration)
    case tonesStopped(at: Duration)
    /// Whether sound can be heard. Failing pauses a block that is playing, or the Ready card of one that needs sound.
    case output(works: Bool, at: Duration)

    // For the drill: ignored unless a block is playing, or as they say.
    case played(Pitch, onset: Duration, at: Duration)
    case typed(NoteName, at: Duration)
    /// The clicks just asked for, as they will be heard.
    case clicksStarted(ClickTrack)
    /// The backing just asked for, as it will be heard.
    case backingStarted(Backing)
    /// What the block's passes are played at, from the next one on: on its Ready card and while paused too.
    case passSettings(PassSettings, at: Duration)
    /// The fade levels reached by now, read again from the log, which has this session's passes too: from the next pass
    /// on.
    case fadeLevels(FadeLevels)
    case hint(isShown: Bool, at: Duration)
    case skip(at: Duration)
    case `repeat`(at: Duration)
}

/// Runs a session's blocks: a pure state machine driven by events and a clock, like the drills it drives.
///
/// A block with a planned length ends only when the player moves on; the others end by themselves (`SessionBlock.End`),
/// with a soft chime, or when the player moves on. The open prompt is then dropped, unrecorded. Blocks left out, and
/// those that need sound when there is none, are passed over.
///
/// Chimes mark 30 s left and the planned end. Each waits for a gap between prompts (in triad drills, voicings), and the next prompt then waits for
/// it to end, since a note played over it wouldn't count. Between passes, a chime also waits for the bar to end, and in
/// progression drills for the time through to end; the next pass or time through then counts in after it.
public struct SessionPlayer: Sendable {
    /// How long a Ready card waits before its block starts by itself.
    public static let readyTime: Duration = .seconds(5)

    /// How much an extend adds.
    public static let extendTime: Duration = .seconds(120)

    /// How long before a block's planned end the first chime is due.
    public static let warningTime: Duration = .seconds(30)

    public let blocks: [SessionBlock]
    public private(set) var stage: SessionStage = .idle

    /// The current block; while finished, the last one reached.
    public private(set) var blockIndex = 0

    /// The current block's drill: nil on its Ready card. Kept, stopped, once the session is finished.
    public private(set) var drill: (any Drill)?

    /// From Start, Ready cards and overtime included but not time paused, up to the last event.
    public private(set) var elapsed: Duration = .zero

    /// What is left of the Ready card; nil unless one is up and counting.
    public private(set) var readyRemaining: Duration?

    /// Ended before its last block was over.
    public private(set) var endedEarly = false

    /// Whether sound can be heard.
    public private(set) var hasSound: Bool

    private let setup: DrillSetup
    private var progress: [Progress]
    private var soundFilter = AppSoundFilter()
    private var lastEvent: Duration = .zero
    /// Waiting for a gap.
    private var dueChime: AppSound?
    /// The block ends when the due chime sounds.
    private var endsOnChime = false
    /// For the app to take.
    private var chimeToPlay: AppSound?
    /// For the app to take.
    private var pendingClicks: [ClickRequest] = []
    /// For the app to take.
    private var pendingBacking: [BackingRequest] = []
    private var settingsByKind: [DrillKind: PassSettings] = [:]
    /// What has been reached, this session's passes included.
    private var fadeLevels: FadeLevels

    /// A block as played.
    private struct Progress: Sendable {
        /// Nil until it starts.
        var spent: Duration?
        var extends = 0
        var attempts: [Attempt] = []
    }

    /// Every block's drill gets `setup`, with a seed of its own.
    public init(blocks: [SessionBlock], setup: DrillSetup, hasSound: Bool = true) {
        self.blocks = blocks
        self.hasSound = hasSound
        self.setup = setup
        fadeLevels = setup.fadeLevels
        progress = blocks.map { _ in Progress() }
    }

    // MARK: - State

    /// The block time spent, overtime included; nil if the block hasn't started.
    public func spent(inBlock index: Int) -> Duration? { progress[index].spent }

    /// How often the block has been extended.
    public func extends(ofBlock index: Int) -> Int { progress[index].extends }

    /// The block's planned length, extends included; nil for a block without one.
    public func length(ofBlock index: Int) -> Duration? {
        blocks[index].length.map { $0 + Self.extendTime * extends(ofBlock: index) }
    }

    /// Until the block's planned end, negative past it; nil for a block without one.
    public func timeLeft(inBlock index: Int) -> Duration? {
        length(ofBlock: index).map { $0 - (progress[index].spent ?? .zero) }
    }

    /// Passed over, planned so or for want of sound, or going to be.
    public func isLeftOut(block index: Int) -> Bool {
        progress[index].spent == nil && (index < blockIndex || !canRun(block: index))
    }

    private func canRun(block index: Int) -> Bool {
        !blocks[index].isLeftOut && (hasSound || !blocks[index].kind.needsSound)
    }

    /// Until the session's end, counting only the Ready cards and planned lengths (or, past one, now): blocks that end
    /// by themselves add nothing.
    public var timeToFinish: Duration {
        guard stage != .finished else { return .zero }
        return blocks.indices[blockIndex...].filter { canRun(block: $0) }.reduce(.zero) { total, index in
            var ready: Duration = progress[index].spent == nil ? Self.readyTime : .zero
            if index == blockIndex, let readyRemaining { ready = readyRemaining }
            return total + ready + max(.zero, timeLeft(inBlock: index) ?? .zero)
        }
    }

    /// What to show for the drill; nil when no prompt is on show.
    public var display: DrillDisplay? { stage == .playing ? drill?.display : nil }

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

    /// The chime to sound now, or to flash if it can't be heard; once. Call it after every event too.
    public mutating func takeChime() -> AppSound? {
        defer { chimeToPlay = nil }
        return chimeToPlay
    }

    /// The clicks asked for since the last call, to be done in order, each start answered with `clicksStarted`. Call it
    /// after every event.
    public mutating func takeClicks() -> [ClickRequest] {
        defer { pendingClicks = [] }
        return pendingClicks
    }

    /// The backing asked for since the last call, to be done in order, each start answered with `backingStarted`. Call
    /// it after every event.
    public mutating func takeBacking() -> [BackingRequest] {
        defer { pendingBacking = [] }
        return pendingBacking
    }

    /// What the block's next pass will be played at, from its Ready card on; nil in blocks without passes.
    public var passSettings: PassSettings? {
        guard stage != .idle, stage != .finished, blocks[blockIndex].kind.hasPasses else { return nil }
        return settingsByKind[blocks[blockIndex].kind] ?? (blocks[blockIndex].setup ?? setup).options.pass
    }

    // MARK: - Events

    public mutating func handle(_ event: SessionEvent) {
        let attemptCount = drill?.attempts.count ?? 0
        act(on: event)
        if endsOnTimesThrough() { dueChime = .softChime }
        soundDueChime(afterAttempt: (drill?.attempts.count ?? 0) > attemptCount)
        if endsOnChime, dueChime == nil {
            endBlock(at: lastEvent)
        } else if stage == .playing, drill?.isRunning == false {
            // Done by itself.
            chimeToPlay = .softChime
            endBlock(at: lastEvent)
        }
        holdForChime()
    }

    /// Whether the block has just gone through as often as it ends after: its chime is then due, and the block ends
    /// with it.
    private mutating func endsOnTimesThrough() -> Bool {
        guard stage == .playing, !endsOnChime, case .afterTimesThrough(let count) = blocks[blockIndex].end,
              let timeThrough = drill?.display?.progression?.timeThrough, timeThrough >= count else { return false }
        endsOnChime = true
        return true
    }

    private mutating func act(on event: SessionEvent) {
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
            case .idle, .paused, .finished: break
            }
        case .pause(let now):
            guard stage == .ready || stage == .playing else { return }
            passTime(to: now)
            pause(at: now)
        case .resume(let now):
            guard stage == .paused else { return }
            passTime(to: now)
            if drill == nil {
                showReady(blockIndex)
            } else if canRun(block: blockIndex) {
                stage = .playing
                // After a held chime, if there is one to be heard. A drill that can be held goes on at once.
                let waits = dueChime != nil && hasSound && drill?.resumesSamePrompt != true
                releaseChime()
                if !waits { send(.resume(at: now)) }
            } else {
                endBlock(at: now)
            }
        case .extend(let now):
            passTime(to: now)
            guard stage == .playing, blocks[blockIndex].length != nil, let left = extended() else { return }
            if (dueChime == .chime && left > Self.warningTime) || (dueChime == .softChime && left > .zero) { dueChime = nil }
        case .end(let now):
            guard stage == .ready || stage == .playing || stage == .paused else { return }
            passTime(to: now)
            endedEarly = !(stage == .playing && isLastBlock && blocks[blockIndex].kind.hasNoPrompts)
            stopDrill(at: now)
            finish()
        case .tick(let now):
            passTime(to: now)
            if let readyRemaining, readyRemaining <= .zero {
                startBlock(at: now)
            } else if !isHeldForChime(at: now) {
                send(drill?.phase == .paused ? .resume(at: now) : .tick(at: now))
            }
        case .output(let works, let now):
            passTime(to: now)
            let failed = hasSound && !works
            hasSound = works
            if failed, stage == .playing || (stage == .ready && !canRun(block: blockIndex)) { pause(at: now) }
        case .soundStarted(let sound, let now, let latency):
            passTime(to: now)
            soundFilter.started(sound, at: now, latency: latency)
            if !sound.isChime { send(.soundStarted(at: now, latency: latency)) }
        case .tonesStopped(let now):
            soundFilter.tonesStopped(at: now)
        case .played(let pitch, let onset, let now):
            passTime(to: now)
            if !soundFilter.ignores(onset: onset), !isHeldForChime(at: now) { send(.played(pitch, onset: onset, at: now)) }
        case .typed(let name, let now):
            passTime(to: now)
            if !isHeldForChime(at: now) { send(.typed(name, at: now)) }
        case .clicksStarted(let track):
            send(.clicksStarted(track))
        case .backingStarted(let backing):
            send(.backingStarted(backing))
        case .passSettings(let new, let now):
            passTime(to: now)
            guard passSettings != nil else { return }
            settingsByKind[blocks[blockIndex].kind] = new
            drill?.handle(.passSettings(new, at: now))
            followDrill()
        case .fadeLevels(let new):
            fadeLevels = new
            drill?.handle(.fadeLevels(new))
        case .hint(let isShown, let now):
            passTime(to: now)
            send(.hint(isShown: isShown, at: now))
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
        case .idle, .paused, .finished:
            return
        case .ready:
            readyRemaining = readyRemaining.map { max(.zero, $0 - passed) }
        case .playing:
            let before = timeLeft(inBlock: blockIndex)
            progress[blockIndex].spent? += passed
            if let before, let after = timeLeft(inBlock: blockIndex) {
                if before > Self.warningTime, after <= Self.warningTime { dueChime = .chime }
                if before > .zero, after <= .zero { dueChime = .softChime }
            }
        }
        elapsed += passed
    }

    private mutating func pause(at now: Duration) {
        send(.pause(at: now))
        stage = .paused
        readyRemaining = nil
    }

    // MARK: - Chimes

    /// Whether the drill is between prompts with a chime sounding: until it ends, only a skip or repeat moves it on.
    private func isHeldForChime(at now: Duration) -> Bool {
        guard soundFilter.isChiming(at: now), drill?.passEnd == nil else { return false }
        return switch drill?.phase {
        case .correct, .timedOut, .paused: true
        case .waiting, .wrong, .idle, nil: false
        }
    }

    /// A prompt that comes up while a chime sounds waits for its end: a sweep is held, so that notes from before the
    /// chime still count; another drill is paused, and the first tick after the chime resumes it.
    private mutating func holdForChime() {
        guard stage == .playing, let drill, let end = soundFilter.chimeEnd(at: lastEvent) else { return }
        if drill.passEnd != nil { return send(.hold(until: end)) }
        switch drill.phase {
        case .waiting, .wrong: send(drill.canHold ? .hold(until: end) : .pause(at: lastEvent))
        case .correct, .timedOut, .paused, .idle: break
        }
    }

    /// Sounds the due chime if this is a gap. Where the next prompt is up already (after a skip) and can't be held, it is
    /// dropped before its sounds play. A flash needs no waiting for.
    private mutating func soundDueChime(afterAttempt: Bool) {
        guard stage == .playing, let dueChime, let drill else { return }
        if let passEnd = drill.passEnd {
            // Planned for, so that no click of the count-in comes first.
            if hasSound { send(.hold(until: max(passEnd, lastEvent) + dueChime.duration + AppSoundFilter.tail)) }
            if !hasSound || lastEvent >= passEnd { releaseChime() }
            return
        }
        if drill.kind.hasPasses, drill.phase != .paused { return }
        switch drill.phase {
        case .correct, .timedOut, .paused, .idle:
            break
        case .waiting, .wrong:
            guard afterAttempt, !drill.isPartWay else { return }
            if hasSound, !drill.canHold { send(.pause(at: lastEvent)) }
        }
        releaseChime()
    }

    private mutating func releaseChime() {
        guard let dueChime else { return }
        chimeToPlay = dueChime
        self.dueChime = nil
    }

    // MARK: - Blocks

    /// Blocks that need sound are passed over when there is none.
    private mutating func showReady(_ first: Int) {
        guard let index = blocks.indices.first(where: { $0 >= first && canRun(block: $0) }) else { return finish() }
        drill = nil
        blockIndex = index
        stage = .ready
        readyRemaining = Self.readyTime
    }

    /// One extend more: what is then left.
    private mutating func extended() -> Duration? {
        progress[blockIndex].extends += 1
        return timeLeft(inBlock: blockIndex)
    }

    /// No block after the current one will run.
    private var isLastBlock: Bool { !blocks.indices.contains { $0 > blockIndex && canRun(block: $0) } }

    private mutating func startBlock(at now: Duration) {
        stage = .playing
        readyRemaining = nil
        progress[blockIndex].spent = .zero
        endsOnChime = false
        var blockSetup = blocks[blockIndex].setup ?? setup
        if let passSettings { blockSetup.options.pass = passSettings }
        blockSetup.seed &+= UInt64(blockIndex)
        blockSetup.fadeLevels = fadeLevels
        drill = blocks[blockIndex].kind.makeDrill(blockSetup)
        send(.start(at: now))
    }

    private mutating func endBlock(at now: Duration) {
        stopDrill(at: now)
        dueChime = nil
        endsOnChime = false
        showReady(blockIndex + 1)
    }

    private mutating func finish() {
        stage = .finished
        readyRemaining = nil
    }

    private mutating func send(_ event: DrillEvent) {
        guard stage == .playing, drill != nil else { return }
        drill?.handle(event)
        progress[blockIndex].attempts = drill?.attempts ?? []
        followDrill()
    }

    private mutating func stopDrill(at now: Duration) {
        drill?.handle(.stop(at: now))
        followDrill()
    }

    private mutating func followDrill() {
        pendingClicks += drill?.takeClicks() ?? []
        pendingBacking += drill?.takeBacking() ?? []
        if let settings = drill?.passSettings { settingsByKind[blocks[blockIndex].kind] = settings }
        if let reached = drill?.fadeLevels { fadeLevels = reached }
    }
}
