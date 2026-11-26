import Foundation
import ListenCore
import Observation
import PracticeCore
import TheoryCore

/// The Drill screen's state: free practice of one drill. Connects the audio input to the PracticeCore drill, and
/// turns the drill's state into what the D4 layout shows.
///
/// One clock for everything the drill sees: host time in seconds (`AudioInputService.hostTimeNow()`), as a
/// `Duration`. Played notes arrive on it from `PlayedNoteFeed`. It outlives its screen, so a paused run does too.
@MainActor @Observable
final class DrillViewModel: MetronomePanelOwner {
    /// What the view draws from the drill, copied after each event and only replaced when it changes.
    struct Snapshot: Equatable {
        var phase: DrillPhase = .idle
        var display: DrillDisplay?
        var attempts: [Attempt] = []
    }

    /// The tuning in Settings. Changing it (or the capo) stops a run, since prompts depend on it.
    var tuning: Tuning = .standard {
        didSet { if tuning != oldValue { stop() } }
    }

    /// The capo in Settings (0–12); frets below it are never prompted.
    var capo = 0 {
        didSet { if capo != oldValue { stop() } }
    }

    /// The position system in Settings, for scale drills. Changing it stops a run of one.
    var positionSystem: Position.System {
        get { options.positionSystem }
        set {
            guard newValue != options.positionSystem else { return }
            if kind.hasPasses { stop() }
            options.positionSystem = newValue
        }
    }

    /// The drill to practise. The view locks it during a run.
    var kind = DrillKind.all[0] {
        didSet {
            guard kind != oldValue else { return }
            isPanelOpen = false
            loadTempo()
            loadBacking()
        }
    }

    /// Where attempts are saved; the view sets it before a run can start.
    @ObservationIgnored var log: AttemptLog?

    /// Where the drill's sounds go; the view sets it before a run can start. None (in `LogCheck`) is silent.
    var soundOutput: AppSoundOutput?

    /// What scale drills are played to, and where their tempos are remembered; the view sets it before a run can start.
    /// None (in `LogCheck`) is silent.
    @ObservationIgnored var metronome: Metronome? {
        didSet {
            loadTempo()
            loadBacking()
        }
    }

    /// What progression drills play over; the view sets it before a run can start. None (in `LogCheck`), or none with
    /// its sounds fetched, plays the backing's beats as clicks on the metronome.
    @ObservationIgnored var backingPlayer: BackingPlayer?

    /// The toolbar's options, shared by every drill. The view locks them during a run; a run uses the options it
    /// started with.
    var options = DrillOptions()

    /// What passes are played at; the tempo ladder moves it too. A change takes effect from the next pass on.
    var passSettings: PassSettings {
        get { options.pass }
        set {
            guard newValue != options.pass else { return }
            setPassSettings(newValue)
            if isRunning { send(.passSettings(newValue, at: clockNow())) }
        }
    }

    private func setPassSettings(_ new: PassSettings) {
        let old = options.pass
        options.pass = new
        if kind.hasPasses, new.tempo != old.tempo || new.holdsTempo != old.holdsTempo || new.ladder != old.ladder {
            metronome?.storeTempo(of: kind, from: new)
        }
    }

    /// Takes up the drill's remembered tempo, which a session may have changed, but for a run that is going.
    private func loadTempo() {
        guard !isRunning || isPaused, kind.hasPasses, let metronome else { return }
        metronome.loadTempo(of: kind, into: &options.pass)
        if isRunning { send(.passSettings(options.pass, at: clockNow())) }
    }

    // MARK: - Progressions

    /// The progression drills' progression: the chosen one, or the first of the key's mode when none is, or the
    /// chosen one is of the other mode. Changing it takes up its remembered style.
    var progression: Progression {
        get {
            options.progression.flatMap { $0.mode == options.key.mode ? $0 : nil }
                ?? Progression.library(options.key.mode)[0]
        }
        set {
            options.progression = newValue
            loadBacking()
        }
    }

    /// The key, for progression drills: changing its mode changes the progression too.
    var progressionKey: Key {
        get { options.key }
        set {
            let old = progression
            options.key = newValue
            if old.mode != newValue.mode { progression = Progression.library(newValue.mode)[0] }
        }
    }

    /// Tempo and style; a change is remembered (the style for the progression).
    var backingSettings: BackingSettings {
        get { options.backing }
        set {
            options.backing = newValue
            metronome?.storeBacking(of: progression, from: newValue)
        }
    }

    /// Takes up the remembered tempo and the progression's style, but for a run that is going.
    private func loadBacking() {
        guard kind.hasBacking, !isRunning, let metronome else { return }
        metronome.loadBacking(of: progression, into: &options.backing)
    }

    /// Whether the input is the Mac's own microphone, which would hear the backing as notes.
    private(set) var isInputBuiltIn = false

    #if DEBUG
    /// For snapshots, where there is no input.
    func setInputBuiltInForSnapshot() { isInputBuiltIn = true }
    #endif

    /// What a progression drill should know about how the backing will be heard: none fetched, or a built-in
    /// microphone.
    var backingNotices: [String] {
        guard kind.hasBacking else { return [] }
        var notices: [String] = []
        if backingPlayer?.hasSounds == false {
            notices.append("No backing sounds: the drill plays clicks. " + BackingSounds.fetchHint)
        }
        if isInputBuiltIn {
            notices.append("The built-in microphone will hear the backing as notes: use the interface, or headphones.")
        }
        return notices
    }

    /// The chosen position of the key's scale, for progression drills; nil if it isn't on the neck.
    var progressionPosition: Position? { setup.progressionPosition }

    /// The run's chords so far, and how they went.
    var chordSummary: ChordSummary { ChordSummary(attempts: snapshot.attempts) }

    /// Those reached by now in what the drill goes through, a session's included.
    private func loggedFadeStages() -> FadeStages? {
        guard kind.fades else { return nil }
        return kind.hasPasses ? log?.fadeStages(in: setup.passPositions.map(\.id), on: [])
            : log?.fadeStages(in: [], on: options.stringSets)
    }

    /// The metronome panel. The view keeps the run's buttons and keys from acting while it is open.
    var isPanelOpen = false {
        didSet { if isPanelOpen != oldValue { panelChanged() } }
    }

    @ObservationIgnored var resumesOnPanelClose = false
    var canPause: Bool { isRunning && !isPaused }

    private(set) var snapshot = Snapshot()

    /// Why the run paused by itself, for the Paused card.
    private(set) var pauseNotice: String?

    /// The audio input, while the screen is open; nil (in `LogCheck`) is no problem.
    private var input: AudioInputState?

    /// The note name being typed, in a drill answered by typing.
    private(set) var nameEntry = NoteNameEntry()

    /// Now on the drill clock, in host seconds; moves with each tick while running (drives the countdown ring).
    private(set) var now: Double = 0

    @ObservationIgnored private var drill = DrillKind.all[0].makeDrill(DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 0))
    @ObservationIgnored private var runLog: RunLog?
    @ObservationIgnored private let ticker = DrillTicker()
    @ObservationIgnored private var soundFilter = AppSoundFilter()
    @ObservationIgnored private let feed = PlayedNoteFeed()

    var fretboard: Fretboard { Fretboard(tuning: tuning, capo: capo) }

    // MARK: - Run control

    /// True from Start to Stop (paused included), or until an "In order (check)" run ends.
    var isRunning: Bool { snapshot.phase != .idle }
    var isPaused: Bool { snapshot.phase == .paused }
    var isCheckRun: Bool { drill.isCheckRun }

    /// Whether the options as they stand are for an "In order (check)" run.
    var isSetToCheck: Bool { kind.offersOrder && options.order == .inOrder }

    /// Why Start is disabled with these options; nil when something can be prompted.
    var nothingToPromptReason: String? { newDrill(seed: 0).nothingToPromptReason }

    /// Why nothing can be heard: a run can't start or resume. Nil when it can.
    var inputProblem: AudioInputProblem? { input?.problem }

    /// Why Start would do nothing; nil when it would start a run, or try the sound output again.
    var startProblem: String? {
        if let reason = inputProblem?.text ?? nothingToPromptReason { return reason }
        return soundOutput?.hasDevice == false ? soundProblem : nil
    }

    /// Why this drill can't be heard, if it needs to be.
    var soundProblem: String? { kind.needsSound ? soundOutput?.problem : nil }

    /// What a run would be made from, but for its seed.
    var setup: DrillSetup {
        var options = options
        if kind.hasBacking { options.progression = progression }
        var setup = DrillSetup(fretboard: fretboard, options: options, seed: 0)
        setup.inputDelay = AudioInputSettings.inputDelay(ofDevice: input?.device?.uid)
        return setup
    }

    private func newDrill(seed: UInt64, fadeStages: FadeStages = FadeStages()) -> any Drill {
        var setup = setup
        setup.seed = seed
        setup.fadeStages = fadeStages
        return kind.makeDrill(setup)
    }

    func start(seed: UInt64 = .random(in: .min ... .max)) {
        loadTempo()
        loadBacking()
        guard !isRunning, inputProblem == nil, nothingToPromptReason == nil, prepareSound() else { return }
        drill = newDrill(seed: seed, fadeStages: loggedFadeStages() ?? FadeStages())
        runLog = log?.run()
        send(.start(at: clockNow()))
        startTicking()
    }

    /// Pauses. By itself, with a notice saying why; that is dropped if the player had already paused it.
    func pause(notice: String? = nil) {
        guard isRunning else { return }
        if isPaused, resumesOnPanelClose {
            resumesOnPanelClose = false
            pauseNotice = notice
        }
        guard !isPaused else { return }
        pauseNotice = notice
        send(.pause(at: clockNow()))
        ticker.stop()
    }

    func resume() {
        guard isPaused, inputProblem == nil, prepareSound() else { return }
        pauseNotice = nil
        loadTempo()
        if let stages = loggedFadeStages() { send(.fadeStages(stages)) }
        send(.resume(at: clockNow()))
        startTicking()
    }

    /// P.
    func togglePause() { isPaused ? resume() : pause() }

    /// S: the next prompt, with no reveal.
    func skip() { send(.skip(at: clockNow())) }

    /// R: what it does is up to the drill.
    func repeatPrompt() { send(.repeat(at: clockNow())) }

    /// Whether H is the drill's: while paused too, so that it doesn't do something else.
    var takesHint: Bool { isRunning && kind.fades }

    /// H held or let go.
    func hint(isShown: Bool) { send(.hint(isShown: isShown, at: clockNow())) }

    func stop() {
        guard isRunning else { return }
        resumesOnPanelClose = false
        send(.stop(at: clockNow()))
        ticker.stop()
    }

    /// The sound output failed or came back. Failing pauses a run that needs it, and one with clicks, which can then go
    /// on by the beats shown.
    func soundProblemChanged() {
        if soundProblem != nil { pause() }
        if kind.hasPasses || kind.hasBacking, let problem = soundOutput?.problem { pause(notice: problem) }
    }

    /// True unless the drill needs sound and there is none. Ready before the clock is read, so that the first sound
    /// and its timer aren't late.
    private func prepareSound() -> Bool {
        guard kind.needsSound, let soundOutput else { return true }
        return soundOutput.prepare()
    }

    /// The audio input changed. Losing it pauses.
    func inputChanged(_ new: AudioInputState) {
        defer { input = new }
        if new.device?.uid != input?.device?.uid {
            isInputBuiltIn = new.device.map { CoreAudioDevices.isBuiltIn(uid: $0.uid) } ?? false
        }
        if let notice = input.flatMap(new.lossNotice) { pause(notice: notice) }
    }

    /// The screen is closing: a run that is going pauses, and what was being heard is forgotten.
    func leave() {
        pause()
        isPanelOpen = false
        input = nil
        feed.reset()
    }

    private func startTicking() {
        ticker.start { [weak self] in
            guard let self else { return }
            send(.tick(at: clockNow()))
            if !isRunning { ticker.stop() }
        }
    }

    private func clockNow() -> Duration {
        let seconds = AudioInputService.hostTimeNow()
        now = seconds
        return .seconds(seconds)
    }

    private func send(_ event: DrillEvent) {
        let oldStart = drill.promptStart
        let wasRunning = drill.isRunning
        drill.handle(event)
        playClicks()
        playBacking()
        playSounds(isNewPrompt: drill.promptStart != oldStart)
        runLog?.update(from: drill)
        if wasRunning, let settings = drill.passSettings, settings != options.pass { setPassSettings(settings) }
        let new = Snapshot(phase: drill.phase, display: drill.display, attempts: drill.attempts)
        if new != snapshot { snapshot = new }
        let entry = nameEntry.following(drill)
        if entry != nameEntry { nameEntry = entry }
    }

    // MARK: - Typing

    /// Whether typed note names go to the drill now.
    var takesNoteNames: Bool { isRunning && kind.usesKeyboard }

    /// A key for `.typesNoteNames`: true when it was the drill's.
    func press(_ key: NoteNameKey) -> Bool {
        guard case .taken(let event) = nameEntry.press(key, for: drill, at: clockNow()) else { return false }
        if let event { send(event) }
        return true
    }

    // MARK: - Sound

    /// Plays what the drill asks for. A new prompt, pausing and stopping cut off what is playing.
    private func playSounds(isNewPrompt: Bool) {
        let requests = drill.takeSounds()
        guard kind.needsSound, let soundOutput else { return }
        if isNewPrompt {
            soundOutput.stopTones()
            soundFilter.tonesStopped(at: .seconds(AudioInputService.hostTimeNow()))
        }
        for request in requests {
            let sound = AppSound.tones(request.tones)
            let start = AudioInputService.hostTimeNow()
            // A failure reaches the screen as the output's problem, which pauses the run.
            guard let latency = soundOutput.play(sound) else { return }
            soundFilter.started(sound, at: .seconds(start), latency: latency)
            drill.handle(.soundStarted(at: .seconds(start), latency: latency))
        }
        if !drill.isRunning || drill.phase == .paused { soundOutput.release() }
    }

    private func playClicks() {
        let requests = drill.takeClicks()
        metronome?.perform(requests) { drill.handle(.clicksStarted($0)) }
    }

    /// The backing the drill asks for: on the backing player with its sounds, or as clicks without them.
    private func playBacking() {
        BackingPlayer.perform(drill.takeBacking(), on: backingPlayer, metronome: metronome) { heard in
            #if DEBUG
            backingForSnapshot = heard
            #endif
            drill.handle(.backingStarted(heard))
        }
    }

    // MARK: - Listening

    /// The consumer for `.listensToAudioInput(_:)`.
    var audioConsumer: AudioInputConsumer {
        feed.consumer { [weak self] notes in self?.heard(notes) }
    }

    private func heard(_ notes: [HeardNote]) {
        guard isRunning else { return }
        for note in notes where !soundFilter.ignores(onset: .seconds(note.onset)) {
            send(.played(note.pitch, onset: .seconds(note.onset), at: .seconds(note.detected)))
        }
    }

    #if DEBUG
    /// The backing as last started, for snapshots to play in time with.
    @ObservationIgnored private(set) var backingForSnapshot: Backing?

    /// Plays notes at onsets on the drill's clock, then moves it to `time`, as if heard then (see `Snapshots`).
    func playForSnapshot(_ notes: [(pitch: Pitch, onset: Duration)], until time: Duration) {
        for note in notes { send(.played(note.pitch, onset: note.onset, at: note.onset + .milliseconds(50))) }
        send(.tick(at: time))
        ticker.stop()
    }

    /// Answers the current prompt, as if a right or wrong note had been played now (see `Snapshots` and `LogCheck`).
    func playForSnapshot(right: Bool) {
        guard let location = drill.rightLocationForSnapshot else { return }
        let pitch = fretboard.pitch(at: location)
        let now = max(clockNow(), drill.promptStart ?? .zero)
        send(.played(right ? pitch : pitch + Interval(1), onset: now, at: now))
    }

    /// Lets the current prompt's time run out now.
    func timeOutForSnapshot() {
        guard let start = drill.promptStart else { return }
        send(.tick(at: start + drill.timeLimit + DrillTiming.detectionGrace))
    }

    /// Names the current prompt, as if typed and submitted now.
    func answerForSnapshot() {
        if let prompt = drill.prompt { send(.typed(prompt.name, at: clockNow())) }
    }
    #endif

    // MARK: - Display

    /// "Standard tuning", plus " · capo 2" with a capo.
    var windowSubtitle: String {
        tuning.displayName + (capo > 0 ? " · capo \(capo)" : "")
    }

    /// The prompt's time left, while it awaits an answer.
    var countdown: DrillCountdown? { DrillCountdown(drill: drill, at: .seconds(now)) }

    var stats: RunStats { RunStats(attempts: snapshot.attempts) }

    /// The run's key, for spelling; nil = sharps.
    var key: Key? { drill.setup.key }

    /// The run's sweeps, in All instances.
    var sweeps: [SweepResult] { drill.sweeps }

    /// The run's passes that were complete, and those that were clean.
    var completePasses: Int { PassResult.passes(in: snapshot.attempts).filter(\.isComplete).count }
    var cleanPasses: Int { PassResult.passes(in: snapshot.attempts).filter(\.isClean).count }

    /// The chosen position, for scale drills; nil if it isn't on the neck.
    var position: Position? { setup.position }

    /// Before Start, the chosen position. Pausing hides it.
    var restingMarkers: [FretboardDiagram.Marker] {
        guard !isPaused, let position else { return [] }
        return position.locations.map { .init($0, of: position.scale, on: fretboard) }
    }

    /// While paused: whether Resume continues the same prompt.
    var resumesSamePrompt: Bool { drill.resumesSamePrompt }

    /// The last ~14 attempts for the strip under the target card, oldest first.
    var recentAttempts: [(id: Int, attempt: Attempt)] {
        let attempts = snapshot.attempts
        let start = max(0, attempts.count - 14)
        return (start..<attempts.count).map { ($0, attempts[$0]) }
    }
}
