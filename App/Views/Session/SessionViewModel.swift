import Foundation
import ListenCore
import Observation
import PracticeCore
import TheoryCore

/// A theme, as shown.
struct SessionTheme: Equatable {
    let theme: Theme
    /// "CAGED A shape"; nil when no position fits the neck.
    let positionName: String?
    /// The position on a whole neck; nil when no position fits it.
    let neck: FretboardDiagram?

    var key: Key { theme.key }

    /// "CAGED A shape · D-G-B".
    var detailText: String { [positionName, theme.stringSet?.name].compactMap { $0 }.joined(separator: " · ") }

    /// The progression and its chords in the key, "I–V–vi–IV: G D Em C"; nil without one.
    var progressionText: String? {
        theme.progression.map { "\($0.name): \($0.chords(in: key).map(\.shortName).joined(separator: " "))" }
    }

    /// "B♭ major · CAGED A shape · D-G-B · I–V–vi–IV".
    var text: String {
        [key.description, detailText, theme.progression?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    init(_ theme: Theme, on fretboard: Fretboard) {
        self.theme = theme
        let position = theme.position(on: fretboard)
        positionName = position.map { "\($0.system.settingsName) \($0.name)" }
        neck = position.map { FretboardDiagram($0, in: theme.key, on: fretboard) }
    }
}

/// The Session screen's state. Connects audio input, keys and the attempt log to the PracticeCore session player, and
/// turns the player's state into what the screen shows. It knows nothing of any particular drill.
///
/// The session's clock is the drill clock: host time, as in `DrillViewModel`.
@MainActor @Observable
final class SessionViewModel: MetronomePanelOwner {
    /// What the view draws from the player, copied after each event and only replaced when it changes.
    struct Snapshot: Equatable {
        var stage: SessionStage = .idle
        var blockIndex = 0
        var blocks: [BlockProgress] = []
        /// Whole seconds left of the Ready card.
        var readySeconds = 0
        var display: DrillDisplay?
        /// What the next pass is played at, in a scale block from its Ready card on.
        var passSettings: PassSettings?
        /// When it will end if it goes on now.
        var finish = Finish()
    }

    /// When a session will end: the time of day, or while paused, how long after resuming.
    struct Finish: Equatable {
        var timeText = ""
        var afterResuming: Duration?
    }

    /// A block in the drills bar.
    struct BlockProgress: Equatable {
        var kind: DrillKind
        /// What is left, "+0:12" in overtime, or for a block that is over, what was spent.
        var timeText: String
        /// Goes on past its planned end.
        var isOvertime: Bool
        /// Of the planned length, 0–1.
        var fraction: Double
    }

    /// The tuning and capo in Settings, for the next session. One that is going keeps its own.
    var tuning: Tuning = .standard
    var capo = 0

    var positionSystem = InstrumentSettings.defaultPositionSystem

    /// The setup choices; the view keeps them.
    var setup = SessionSetup()

    /// Where attempts are saved; the view sets it before a session can start.
    @ObservationIgnored var log: AttemptLog?

    /// Where drills' sounds go; the view sets it. None (in `LogCheck`): no drill that needs sound.
    var soundOutput: AppSoundOutput?

    /// What scale blocks are played to, and where their tempos are remembered; the view sets it. None (in `LogCheck`) is
    /// silent.
    @ObservationIgnored var metronome: Metronome? {
        didSet { if stage == .paused { loadPassSettings() } }
    }

    /// What progression blocks play over; the view sets it. None (in `LogCheck`), or none with its sounds fetched, plays
    /// the backing's beats as clicks on the metronome.
    @ObservationIgnored var backingPlayer: BackingPlayer?

    /// The time signature and emphasis in Settings.
    var meter = Meter(.fourFour) {
        didSet { if meter != oldValue { passSettings?.meter = meter } }
    }

    /// The audio input, while the screen is open; nil (in `LogCheck`) is no problem.
    private var input: AudioInputState?

    /// How the backing will be heard. Settable for snapshots, where there is no input.
    var backingHearing = BackingHearing()

    private(set) var snapshot = Snapshot()

    /// The note name being typed, in a drill answered by typing.
    private(set) var nameEntry = NoteNameEntry()

    /// The finished session's, until Done.
    private(set) var summary: SessionSummary?

    /// The day's theme while setting up; from Start until Done, the session's, even past midnight.
    private(set) var theme: SessionTheme?

    /// Whether the theme can still be rerolled: no session has been started that day.
    private(set) var canReroll = false

    /// The neck the session was started on.
    private(set) var fretboard = Fretboard(tuning: .standard)

    /// The fret range the session was started with.
    private(set) var frets = 0...0

    /// The positions its passes go through.
    @ObservationIgnored private var passPositions: [Position.ID] = []
    /// The string sets triads are on.
    @ObservationIgnored private var stringSets: Set<StringSet> = []

    /// Why the session paused by itself, for the Paused screen.
    private(set) var pauseNotice: String?
    @ObservationIgnored private var isPausedForSound = false

    /// A chime that couldn't be heard, while it flashes.
    private(set) var flash: AppSound?
    @ObservationIgnored private var flashEnd: Task<Void, Never>?

    /// Whether the Paused screen asks if the session should end.
    private(set) var asksToEnd = false

    /// Now on the session's clock, in host seconds; moves with each tick (drives the countdown ring).
    private(set) var now: Double = 0

    @ObservationIgnored private var player: SessionPlayer?
    @ObservationIgnored private var record: PracticeSession?
    @ObservationIgnored private var runLog: (blockIndex: Int, log: RunLog)?
    @ObservationIgnored private let ticker = DrillTicker()
    @ObservationIgnored private let feed = PlayedNoteFeed()

    var stage: SessionStage { snapshot.stage }

    /// From Start until it is finished.
    var isActive: Bool { stage == .ready || stage == .playing || stage == .paused }

    /// The current block's drill; nil before Start.
    var blockKind: DrillKind? { snapshot.blocks.indices.contains(snapshot.blockIndex) ? snapshot.blocks[snapshot.blockIndex].kind : nil }

    // MARK: - Setup

    private func drillSetup(seed: UInt64) -> DrillSetup {
        let fretboard = Fretboard(tuning: tuning, capo: capo)
        var drillSetup = DrillSetup(fretboard: fretboard, options: setup.drillOptions(on: fretboard), seed: seed)
        if let theme { drillSetup.follow(theme.theme) }
        // The tempo and the progression's style, as free practice left them.
        if let progression = drillSetup.options.progression {
            metronome?.loadBacking(of: progression, into: &drillSetup.options.backing)
        }
        drillSetup.inputDelay = AudioInputSettings.inputDelay(ofDevice: input?.device?.uid)
        return drillSetup
    }

    /// Whether sound can be heard, as far as is known.
    private var hasSound: Bool { soundOutput.map { $0.problem == nil } ?? false }

    /// What a session without sound does differently; nil with sound.
    var noSoundNotice: String? { hasSound ? nil : SessionPlanner.noSoundNotice(from: DrillKind.all) }

    /// Why there are no triads; nil when there are, or nothing at all can be prompted.
    var noTriadsNotice: String? {
        nothingToPromptReason == nil ? SessionPlanner.noTriadsNotice(from: DrillKind.all, for: drillSetup(seed: 0)) : nil
    }

    /// Why there are no progressions; nil when there are, or nothing at all can be prompted.
    var noProgressionsNotice: String? {
        nothingToPromptReason == nil
            ? SessionPlanner.noProgressionsNotice(from: DrillKind.all, for: drillSetup(seed: 0)) : nil
    }

    /// Whether a progression block is planned, and its backing would be heard as notes or not at all; for setup.
    var backingNotices: [String] {
        guard plan().contains(where: \.kind.hasBacking) else { return [] }
        return backingHearing.notices(hasSounds: backingPlayer?.hasSounds, player: "Progressions")
    }

    /// The blocks a session would have, of the drills that have something to prompt, and can be heard if they need to be.
    func plan(on date: Date = .now) -> [SessionBlock] {
        let drills = SessionPlanner.drills(from: DrillKind.all, for: drillSetup(seed: 0), hasSound: hasSound)
        return SessionPlanner.plan(drills, budget: setup.budget, day: Calendar.dayNumber(of: date))
    }

    /// Why no drill can prompt anything; nil when one can.
    var nothingToPromptReason: String? {
        SessionPlanner.nothingToPromptReason(from: DrillKind.all, for: drillSetup(seed: 0), hasSound: hasSound)
    }

    /// Why nothing can be heard: a session can't start or resume. Nil when it can.
    var inputProblem: AudioInputProblem? { input?.problem }

    /// Why a session can't start; nil when it can.
    var problem: SessionProblem? {
        inputProblem.map(SessionProblem.input) ?? nothingToPromptReason.map(SessionProblem.nothingToPrompt)
    }

    /// The audio input changed. Losing it pauses.
    func inputChanged(_ new: AudioInputState) {
        defer { input = new }
        backingHearing.inputChanged(from: input, to: new)
        if let notice = input.flatMap(new.lossNotice) { pause(notice: notice) }
    }

    // MARK: - Theme

    /// When it changes, the theme to show may have changed too.
    struct ThemeNeck: Hashable {
        var tuning: Tuning
        var capo: Int
        var positionSystem: Position.System
        var isSettingUp: Bool
    }

    var themeNeck: ThemeNeck {
        ThemeNeck(tuning: tuning, capo: capo, positionSystem: positionSystem, isSettingUp: stage == .idle)
    }

    /// Shows the day's theme, picking and saving it if need be. A session that has started keeps its own.
    func showTheme(on date: Date = .now) {
        guard stage == .idle, let log else { return }
        let fretboard = Fretboard(tuning: tuning, capo: capo)
        let shown = SessionTheme(log.theme(on: date, fretboard: fretboard, system: positionSystem), on: fretboard)
        if theme != shown { theme = shown }
        canReroll = !log.hasStartedSession(on: date)
    }

    func reroll(on date: Date = .now) {
        guard stage == .idle else { return }
        log?.rerollTheme(on: date, fretboard: Fretboard(tuning: tuning, capo: capo), system: positionSystem)
        showTheme(on: date)
    }

    // MARK: - Control

    func start(on date: Date = .now, seed: UInt64 = .random(in: .min ... .max)) {
        guard stage == .idle, problem == nil else { return }
        showTheme(on: date)
        // Tried before planning, so that a session without sound is planned as one.
        soundOutput?.prepare()
        let blocks = plan(on: date)
        var drillSetup = drillSetup(seed: seed)
        passPositions = drillSetup.passPositions.map(\.id)
        stringSets = drillSetup.options.stringSets
        drillSetup.fadeStages = log?.fadeStages(in: passPositions, on: stringSets) ?? FadeStages()
        fretboard = drillSetup.fretboard
        frets = drillSetup.options.frets
        player = SessionPlayer(blocks: blocks, setup: drillSetup, hasSound: hasSound)
        record = PracticeSession(
            day: Calendar.practiceDay(of: date), startedAt: date, budgetMinutes: setup.minutes,
            naturalsOnly: setup.notes == .naturals, wholeNeck: setup.range == .wholeNeck,
            blocks: blocks.map { SessionBlockRecord(drill: $0.kind.id, plannedSeconds: $0.length / .seconds(1)) })
        record?.theme = theme?.theme
        send(.start(at: clockNow()))
        startTicking()
    }

    /// Space.
    func next() { send(.next(at: clockNow())) }

    /// +: 2 minutes more for the block.
    func extend() {
        send(.extend(at: clockNow()))
        if let player { updateRecord(from: player) }
    }

    /// S.
    func skip() { send(.skip(at: clockNow())) }

    /// R: what it does is up to the drill.
    func repeatPrompt() { send(.repeat(at: clockNow())) }

    /// P. Also by itself, with a notice saying why; that is dropped if it was already paused.
    func pause(notice: String? = nil) {
        if resumesOnPanelClose {
            resumesOnPanelClose = false
            pauseNotice = notice
        }
        guard isActive, stage != .paused else { return }
        pauseNotice = notice
        isPausedForSound = false
        send(.pause(at: clockNow()))
    }

    /// P while paused.
    func resume() {
        guard stage == .paused, inputProblem == nil else { return }
        // Ready before the clock is read, so that the first sound and its timer aren't late.
        soundOutput?.prepare()
        soundChanged()
        pauseNotice = nil
        asksToEnd = false
        loadPassSettings()
        // Free practice may have moved them.
        if let log { send(.fadeStages(log.fadeStages(in: passPositions, on: stringSets))) }
        send(.resume(at: clockNow()))
    }

    /// The sound output failed or came back. Failing mid-block pauses, with a notice.
    func soundChanged() {
        guard let player, isActive, player.hasSound != hasSound else { return }
        // On a scale block's Ready card, losing it wouldn't have.
        let losesPanelResume = resumesOnPanelClose && player.drill != nil
        let wasPaused = stage == .paused && !losesPanelResume
        send(.output(works: hasSound, at: clockNow()))
        if hasSound, isPausedForSound {
            pauseNotice = nil
            isPausedForSound = false
        } else if !hasSound, !wasPaused, stage == .paused {
            if losesPanelResume { resumesOnPanelClose = false }
            let resuming = blockKind?.needsSound == true ? "Resuming goes on without this drill."
                : blockKind?.hasPasses == true || blockKind?.hasBacking == true ? "Resuming goes on by the beats shown, and chimes flash." : "Chimes will flash."
            pauseNotice = [soundOutput?.problem, resuming].compactMap { $0 }.joined(separator: " ")
            isPausedForSound = true
        }
    }

    /// Esc: pauses, and asks before ending.
    func askToEnd() {
        pause()
        asksToEnd = stage == .paused
    }

    /// Esc again: stays paused.
    func cancelEnd() { asksToEnd = false }

    /// Ends the session early.
    func end() {
        asksToEnd = false
        resumesOnPanelClose = false
        isPanelOpen = false
        send(.end(at: clockNow()))
    }

    /// The screen is closing: a session that is going pauses, and what was being heard is forgotten.
    func leave() {
        pause()
        isPanelOpen = false
        asksToEnd = false
        input = nil
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

    // MARK: - Metronome

    /// What the next pass is played at, in a scale block from its Ready card on; nil otherwise. The tempo ladder moves it
    /// too.
    var passSettings: PassSettings? {
        get { snapshot.passSettings }
        set {
            guard let newValue, newValue != snapshot.passSettings else { return }
            send(.passSettings(newValue, at: clockNow()))
        }
    }

    /// Takes up the block's drill's remembered tempo, which free practice may have changed, and the meter in Settings.
    private func loadPassSettings() {
        guard var settings = passSettings, let blockKind else { return }
        settings.meter = meter
        metronome?.loadTempo(of: blockKind, into: &settings)
        passSettings = settings
    }

    /// The metronome panel, in scale blocks; it pauses a Ready card too. The view keeps the session's keys from acting
    /// while it is open.
    var isPanelOpen = false {
        didSet { if isPanelOpen != oldValue { panelChanged() } }
    }

    @ObservationIgnored var resumesOnPanelClose = false
    var canPause: Bool { isActive && stage != .paused }

    /// Whether H is the drill's: on Ready cards and while paused too, so that it doesn't do something else.
    var takesHint: Bool { isActive && blockKind?.fades == true && !isPanelOpen }

    /// H held or let go.
    func hint(isShown: Bool) { send(.hint(isShown: isShown, at: clockNow())) }

    private func startTicking() {
        ticker.start { [weak self] in
            if let self { send(.tick(at: clockNow())) }
        }
    }

    private func clockNow() -> Duration {
        let seconds = hostTimeNow()
        now = seconds
        return .seconds(seconds)
    }

    #if DEBUG
    @ObservationIgnored private var skippedTime = 0.0
    private func hostTimeNow() -> Double { AudioInputService.hostTimeNow() + skippedTime }
    #else
    private func hostTimeNow() -> Double { AudioInputService.hostTimeNow() }
    #endif

    // MARK: - The player

    private func send(_ event: SessionEvent) {
        guard var player, player.stage != .finished else { return }
        let before = (stage: player.stage, promptStart: player.drill?.promptStart, block: player.blockIndex,
                      settings: player.passSettings)
        player.handle(event)
        let sounds = player.takeSounds()
        let chime = player.takeChime()
        self.player = player

        playClicks()
        playBacking()
        playSounds(sounds, isNewPrompt: player.drill?.promptStart != before.promptStart)
        if let chime {
            play(chime)
            // The count-in waits for it.
            playClicks()
            playBacking()
        }
        if let settings = player.passSettings, let old = before.settings, player.blockIndex == before.block,
           settings.tempo != old.tempo || settings.holdsTempo != old.holdsTempo || settings.ladder != old.ladder {
            metronome?.storeTempo(of: player.blocks[player.blockIndex].kind, from: settings)
        }
        logAttempts(of: player)
        if player.stage != before.stage {
            prepareSound(for: player)
            updateRecord(from: player)
        }
        if player.stage == .paused || player.stage == .finished {
            ticker.stop()
        } else if before.stage == .paused {
            startTicking()
        }
        if player.stage == .finished { summary = player.summary }
        let new = Snapshot(of: player)
        if new != snapshot { snapshot = new }
        if let drill = player.drill { followTyping(drill) } else { nameEntry = NoteNameEntry() }
        if player.stage == .ready, before.stage != .ready { loadPassSettings() }
    }

    private func playClicks() {
        let requests = player?.takeClicks() ?? []
        metronome?.perform(requests) { player?.handle(.clicksStarted($0)) }
    }

    /// The backing a progression block asks for: on the backing player with its sounds, or as clicks without them.
    private func playBacking() {
        let requests = player?.takeBacking() ?? []
        BackingPlayer.perform(requests, on: backingPlayer, metronome: metronome) { heard in
            #if DEBUG
            backingForSnapshot = heard
            #endif
            player?.handle(.backingStarted(heard))
        }
    }

    private func logAttempts(of player: SessionPlayer) {
        guard let log, let record, let drill = player.drill else { return }
        if runLog?.blockIndex != player.blockIndex {
            runLog = (player.blockIndex, log.run(session: record, blockIndex: player.blockIndex))
        }
        runLog?.log.update(from: drill)
    }

    /// Plays what the drill asks for. A new prompt, or none, cuts off what is playing.
    private func playSounds(_ requests: [DrillSoundRequest], isNewPrompt: Bool) {
        guard let soundOutput else { return }
        if isNewPrompt {
            soundOutput.stopTones()
            player?.handle(.tonesStopped(at: .seconds(hostTimeNow())))
        }
        for request in requests { play(.tones(request.tones)) }
    }

    /// Plays a sound. A chime that can't be heard flashes; a drill's failing is the output's problem, which pauses.
    private func play(_ sound: AppSound) {
        let start = hostTimeNow()
        if let latency = soundOutput?.play(sound) {
            player?.handle(.soundStarted(sound, at: .seconds(start), latency: latency))
        } else if sound.isChime {
            flash = sound
            flashEnd?.cancel()
            flashEnd = Task { [weak self] in
                try? await Task.sleep(for: sound.duration)
                if !Task.isCancelled { self?.flash = nil }
            }
        }
    }

    /// The output runs all through a session, so that its sounds and their timers aren't late. It stops while paused:
    /// `resume` starts it again.
    private func prepareSound(for player: SessionPlayer) {
        if player.stage != .finished, player.stage != .paused {
            soundOutput?.prepare()
        } else {
            soundOutput?.release()
        }
    }

    /// Only a session with attempts has been inserted, and only then is there anything to save.
    private func updateRecord(from player: SessionPlayer) {
        guard let record else { return }
        record.blocks = record.blocks.enumerated().map { index, block in
            var block = block
            block.extends = player.extends(ofBlock: index)
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

    // MARK: - Typing

    /// Whether typed note names are the drill's now: while paused too, so that a late one doesn't do something else.
    var takesNoteNames: Bool { (stage == .playing || stage == .paused) && blockKind?.usesKeyboard == true }

    /// A key for `.typesNoteNames`: true when it was the drill's.
    func press(_ key: NoteNameKey) -> Bool {
        guard takesNoteNames, let drill = player?.drill,
              case .taken(let event) = nameEntry.press(key, for: drill, at: clockNow()) else { return false }
        if case .typed(let name, let now) = event { send(.typed(name, at: now)) }
        return true
    }

    private func followTyping(_ drill: any Drill) {
        let entry = nameEntry.following(drill)
        if entry != nameEntry { nameEntry = entry }
    }

    // MARK: - Display

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
    /// Moves the session's clock on.
    func passTimeForSnapshot(_ seconds: Double) {
        skippedTime += seconds
        send(.tick(at: clockNow()))
    }

    /// Answers the current prompt, as if played or typed now (see `Snapshots`).
    func answerForSnapshot(right: Bool) {
        guard let drill = player?.drill, let prompt = drill.prompt else { return }
        let now = max(clockNow(), drill.promptStart ?? .zero)
        if blockKind?.usesKeyboard == true {
            send(.typed(right ? prompt.name : prompt.pitchClass == PitchClass(0) ? .g : .c, at: now))
        } else if let location = drill.rightLocationForSnapshot {
            let pitch = fretboard.pitch(at: location)
            send(.played(right ? pitch : pitch + Interval(1), onset: now, at: now))
        }
    }

    /// The backing as last started, for snapshots to play in time with.
    @ObservationIgnored private(set) var backingForSnapshot: Backing?

    /// In a progression block, plays the drawn path in time with the backing as heard (see
    /// `progressionNotesForSnapshot`); then moves the clock to `beat`, counted from the count-in's first.
    func playProgressionForSnapshot(chords count: Int, wrong: Set<Int> = [], partial: Int = 0, untilBeat beat: Double) {
        guard let backing = backingForSnapshot, let kind = blockKind, let theme = theme?.theme,
              let progression = theme.progression, let position = theme.position(on: fretboard) else { return }
        let notes = progressionNotesForSnapshot(kind, progression, in: theme.key, position: position, on: fretboard,
                                                backing: backing, chords: count, wrong: wrong, partial: partial)
        for note in notes { send(.played(note.pitch, onset: note.onset, at: note.onset + .milliseconds(50))) }
        let end = backing.start + Duration.seconds(60) / backing.bpm * beat
        skippedTime += max(0, end / .seconds(1) - hostTimeNow())
        send(.tick(at: clockNow()))
    }

    /// Lets the current prompt's time run out.
    func timeOutForSnapshot() {
        guard let drill = player?.drill, let left = drill.timeRemaining(at: clockNow()) else { return }
        passTimeForSnapshot((left + DrillTiming.detectionGrace) / .seconds(1))
    }
    #endif
}

extension SessionViewModel.Snapshot {
    @MainActor fileprivate init(of player: SessionPlayer) {
        stage = player.stage
        blockIndex = player.blockIndex
        readySeconds = player.readyRemaining.map { Int(($0 / .seconds(1)).rounded(.up)) } ?? 0
        display = player.display
        passSettings = player.passSettings
        finish = player.stage == .paused ? .init(afterResuming: player.timeToFinish)
            : .init(timeText: sessionFinishText(player.timeToFinish, after: .now))
        blocks = player.blocks.indices.map { index in
            let spent = player.spent(inBlock: index)
            let isOver = spent != nil && index < player.blockIndex
            let left = player.timeLeft(inBlock: index)
            let isOvertime = !isOver && left < .zero
            let timeText = if player.isLeftOut(block: index) { "no sound" }
                else if isOver { clockText(spent ?? .zero) }
                else if isOvertime { "+" + clockText(.zero - left) }
                else { clockText(left, rounding: .up) }
            return .init(
                kind: player.blocks[index].kind,
                timeText: timeText,
                isOvertime: isOvertime,
                // In 200ths, so that the bar moves smoothly without a redraw on every tick.
                fraction: isOver ? 1 : min(1, ((spent ?? .zero) / player.length(ofBlock: index) * 200).rounded(.down) / 200))
        }
    }
}

/// "Ends 18:42".
func sessionFinishText(_ timeLeft: Duration, after date: Date) -> String {
    "Ends " + (date + timeLeft / .seconds(1)).formatted(date: .omitted, time: .shortened)
}
