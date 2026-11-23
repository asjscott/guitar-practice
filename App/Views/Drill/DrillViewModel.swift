import Foundation
import Observation
import PracticeCore
import TheoryCore

/// The Drill screen's state: free practice of one drill. Connects the audio input to the PracticeCore drill, and
/// turns the drill's state into what the D4 layout shows.
///
/// One clock for everything the drill sees: host time in seconds (`AudioInputService.hostTimeNow()`), as a
/// `Duration`. Played notes arrive on it from `PlayedNoteFeed`. While a run goes, a main-actor timer ticks the
/// drill about 30 times a second, so timeouts and the next prompt happen hands-free.
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

    /// The toolbar's options, shared by every drill. The view locks them during a run; a run uses the options it
    /// started with.
    var options = DrillOptions()

    private(set) var snapshot = Snapshot()

    /// Now on the drill clock, in host seconds; moves with each tick while running (drives the countdown ring).
    private(set) var now: Double = 0

    @ObservationIgnored private var drill = DrillKind.all[0].makeDrill(DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 0))
    @ObservationIgnored private var runLog: RunLog?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let feed = PlayedNoteFeed()

    /// How often the engine is ticked while running.
    private static let tickInterval: Duration = .milliseconds(33)

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

    private func newDrill(seed: UInt64) -> any Drill {
        kind.makeDrill(DrillSetup(fretboard: fretboard, options: options, seed: seed))
    }

    func start(seed: UInt64 = .random(in: .min ... .max)) {
        guard !isRunning, nothingToPromptReason == nil else { return }
        drill = newDrill(seed: seed)
        runLog = log?.run()
        send(.start(at: clockNow()))
        startTicking()
    }

    func togglePause() {
        guard isRunning else { return }
        if isPaused {
            send(.resume(at: clockNow()))
            startTicking()
        } else {
            send(.pause(at: clockNow()))
            stopTicking()
        }
    }

    /// S: the next prompt, with no reveal.
    func skip() { send(.skip(at: clockNow())) }

    /// R: what it does is up to the drill.
    func repeatPrompt() { send(.repeat(at: clockNow())) }

    func stop() {
        guard isRunning else { return }
        send(.stop(at: clockNow()))
        stopTicking()
    }

    /// The screen is closing: end the run (no summary is shown) and forget what was being heard.
    func leave() {
        stop()
        feed.reset()
    }

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                guard let self, !Task.isCancelled else { return }
                send(.tick(at: clockNow()))
                if !isRunning { stopTicking() }
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    private func clockNow() -> Duration {
        let seconds = AudioInputService.hostTimeNow()
        now = seconds
        return .seconds(seconds)
    }

    private func send(_ event: DrillEvent) {
        drill.handle(event)
        runLog?.update(from: drill)
        let new = Snapshot(phase: drill.phase, display: drill.display, attempts: drill.attempts)
        if new != snapshot { snapshot = new }
    }

    // MARK: - Listening

    /// The consumer for `.listensToAudioInput(_:)`.
    var audioConsumer: AudioInputConsumer {
        feed.consumer { [weak self] notes in self?.heard(notes) }
    }

    private func heard(_ notes: [HeardNote]) {
        guard isRunning else { return }
        for note in notes {
            send(.played(note.pitch, onset: .seconds(note.onset), at: .seconds(note.detected)))
        }
    }

    #if DEBUG
    /// Answers the current prompt, as if a right or wrong note had been played now (see `Snapshots` and `LogCheck`).
    func playForSnapshot(right: Bool) {
        guard let prompt = drill.prompt,
              let location = prompt.target ?? fretboard.locations(of: prompt.pitchClass, onString: prompt.string,
                                                                  frets: options.frets).first else { return }
        let pitch = fretboard.pitch(at: location)
        let now = clockNow()
        send(.played(right ? pitch : pitch + Interval(1), onset: now, at: now))
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

    /// The last ~14 attempts for the strip under the flashcard, oldest first.
    var recentAttempts: [(id: Int, attempt: Attempt)] {
        let attempts = snapshot.attempts
        let start = max(0, attempts.count - 14)
        return (start..<attempts.count).map { ($0, attempts[$0]) }
    }
}
