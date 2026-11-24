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
final class DrillViewModel {
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

    /// The drill to practise. The view locks it during a run.
    var kind = DrillKind.all[0]

    /// Where attempts are saved; the view sets it before a run can start.
    @ObservationIgnored var log: AttemptLog?

    /// Where the drill's sounds go; the view sets it before a run can start. None (in `LogCheck`) is silent.
    var soundOutput: AppSoundOutput?

    /// The toolbar's options, shared by every drill. The view locks them during a run; a run uses the options it
    /// started with.
    var options = DrillOptions()

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

    private func newDrill(seed: UInt64) -> any Drill {
        kind.makeDrill(DrillSetup(fretboard: fretboard, options: options, seed: seed))
    }

    func start(seed: UInt64 = .random(in: .min ... .max)) {
        guard !isRunning, inputProblem == nil, nothingToPromptReason == nil, prepareSound() else { return }
        drill = newDrill(seed: seed)
        runLog = log?.run()
        send(.start(at: clockNow()))
        startTicking()
    }

    /// Pauses. By itself, with a notice saying why; that is dropped if it was already paused.
    func pause(notice: String? = nil) {
        guard isRunning, !isPaused else { return }
        pauseNotice = notice
        send(.pause(at: clockNow()))
        ticker.stop()
    }

    func resume() {
        guard isPaused, inputProblem == nil, prepareSound() else { return }
        pauseNotice = nil
        send(.resume(at: clockNow()))
        startTicking()
    }

    /// P.
    func togglePause() { isPaused ? resume() : pause() }

    /// S: the next prompt, with no reveal.
    func skip() { send(.skip(at: clockNow())) }

    /// R: what it does is up to the drill.
    func repeatPrompt() { send(.repeat(at: clockNow())) }

    func stop() {
        guard isRunning else { return }
        send(.stop(at: clockNow()))
        ticker.stop()
    }

    /// The sound output failed or came back: a run that needs it pauses.
    func soundProblemChanged() {
        if soundProblem != nil { pause() }
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
        if let notice = input.flatMap(new.lossNotice) { pause(notice: notice) }
    }

    /// The screen is closing: a run that is going pauses, and what was being heard is forgotten.
    func leave() {
        pause()
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
        drill.handle(event)
        playSounds(isNewPrompt: drill.promptStart != oldStart)
        runLog?.update(from: drill)
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
    /// Answers the current prompt, as if a right or wrong note had been played now (see `Snapshots` and `LogCheck`).
    func playForSnapshot(right: Bool) {
        guard let prompt = drill.prompt,
              let location = prompt.target ?? triadLocation(for: prompt) ?? fretboard.locations(of: prompt.pitchClass, onString: prompt.string,
                                                                  frets: options.frets).first else { return }
        let pitch = fretboard.pitch(at: location)
        let now = max(clockNow(), drill.promptStart ?? .zero)
        send(.played(right ? pitch : pitch + Interval(1), onset: now, at: now))
    }

    private func triadLocation(for prompt: NotePrompt) -> FretboardLocation? {
        (drill as? PromptDrill<TriadPlayItRules>)?.correctLocations.first { $0.string == prompt.string }
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

    /// While paused: whether Resume continues the same prompt.
    var resumesSamePrompt: Bool { drill.resumesSamePrompt }

    /// The last ~14 attempts for the strip under the target card, oldest first.
    var recentAttempts: [(id: Int, attempt: Attempt)] {
        let attempts = snapshot.attempts
        let start = max(0, attempts.count - 14)
        return (start..<attempts.count).map { ($0, attempts[$0]) }
    }
}
