import Foundation
import ListenCore
import Observation
import PracticeCore
import TheoryCore

/// The Note → play it drill screen's state. Connects the audio input (through a ListenCore listener) to the
/// PracticeCore drill engine, and turns the engine's state into what the D4 layout shows.
///
/// One clock for everything the engine sees: host time in seconds (`AudioInputService.hostTimeNow()`), as a
/// `Duration`. Start, pause, resume, stop and ticks use it directly; a played note's onset, which the listener
/// gives in stream seconds, is moved onto it with the block's host-time offset. While a run goes, a main-actor
/// timer ticks the engine about 30 times a second, so timeouts and the next prompt happen hands-free.
@MainActor @Observable
final class DrillViewModel {
    /// What the view draws from the engine, copied after each event and only replaced when it changes.
    struct Snapshot: Equatable {
        var phase: NotePlayItDrill.Phase = .idle
        var prompt: NotePrompt?
        var attempts: [Attempt] = []
        var litLocation: FretboardLocation?
        var revealedLocations: [FretboardLocation] = []
    }

    /// The tuning in Settings. Changing it (or the capo) stops a run, since prompts depend on it.
    var tuning: Tuning = .standard {
        didSet { if tuning != oldValue { fretboardChanged() } }
    }

    /// The capo in Settings (0–12); frets below it are never prompted.
    var capo = 0 {
        didSet { if capo != oldValue { fretboardChanged() } }
    }

    /// The toolbar's options. The view locks them during a run; a run uses the options it started with.
    var options = NotePlayItOptions()

    private(set) var snapshot = Snapshot()

    /// Now on the drill clock, in host seconds; moves with each tick while running (drives the countdown ring).
    private(set) var now: Double = 0

    @ObservationIgnored private var drill = NotePlayItDrill(fretboard: Fretboard(tuning: .standard), options: .init(), seed: 0)
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let listener = LockedListener()

    /// How often the engine is ticked while running.
    private static let tickInterval: Duration = .milliseconds(33)

    var fretboard: Fretboard { Fretboard(tuning: tuning, capo: capo) }

    // MARK: - Run control

    /// True from Start to Stop (paused included), or until an "In order (check)" run ends.
    var isRunning: Bool { snapshot.phase != .idle }
    var isPaused: Bool { snapshot.phase == .paused }
    var isCheckRun: Bool { drill.options.order == .inOrder }

    func start(seed: UInt64 = .random(in: .min ... .max)) {
        guard !isRunning else { return }
        drill = NotePlayItDrill(fretboard: fretboard, options: options, seed: seed)
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

    func stop() {
        guard isRunning else { return }
        send(.stop(at: clockNow()))
        stopTicking()
    }

    /// The screen is closing: end the run (no summary is shown) and forget what the listener was tracking.
    func leave() {
        stop()
        listener.reset()
    }

    private func fretboardChanged() {
        stop()
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

    private func send(_ event: NotePlayItDrill.Event) {
        drill.handle(event)
        let new = Snapshot(phase: drill.phase, prompt: drill.prompt, attempts: drill.attempts,
                           litLocation: drill.litLocation, revealedLocations: drill.revealedLocations)
        if new != snapshot { snapshot = new }
    }

    // MARK: - Listening

    /// The consumer for `.listensToAudioInput(_:)`: runs the listener on the tap thread and hands played
    /// notes, on the drill clock, to the engine on the main actor.
    var audioConsumer: AudioInputConsumer {
        let listener = self.listener
        return { [weak self] block in
            let playedNotes = listener.process(block).playedNotes
            guard !playedNotes.isEmpty else { return }
            let clock = StreamClock(block: block)
            let heard = playedNotes.map { HeardNote(pitch: Pitch($0.midiNote), onset: clock.hostTime(ofStreamTime: $0.onset)) }
            let detected = clock.blockEnd
            Task { @MainActor [weak self] in self?.heard(heard, detectedAt: detected) }
        }
    }

    private func heard(_ notes: [HeardNote], detectedAt detected: Double) {
        guard isRunning else { return }
        for note in notes {
            send(.played(note.pitch, onset: .seconds(note.onset), at: .seconds(detected)))
        }
    }

    #if DEBUG
    /// Answers the current prompt, as if a right or wrong note had been played now (see `Snapshots`).
    func playForSnapshot(right: Bool) {
        guard let location = drill.correctLocations.first else { return }
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

    /// The neck: no labels except on the answer, the prompted string highlighted while running, the played
    /// location lit after a right answer, every right location on the string revealed after a timeout.
    var diagram: FretboardDiagram {
        var diagram = FretboardDiagram(stringNames: fretboard.stringNames(in: nil).map(\.description))
        diagram.capo = capo
        diagram.labelMode = .shown
        let name = snapshot.prompt?.noteName ?? ""
        if let lit = snapshot.litLocation {
            diagram.markers = [.init(location: lit, label: name, role: .root)]
        } else {
            diagram.markers = snapshot.revealedLocations.map { .init(location: $0, label: name, role: .tone) }
        }
        diagram.highlightedString = isRunning ? snapshot.prompt?.string : nil
        return diagram
    }

    /// The flashcard's second line: "on string 3 (G)", plus the fret being checked in an "In order (check)" run.
    var promptStringText: String {
        guard let prompt = snapshot.prompt else { return "" }
        let fret = prompt.target.map { " · fret \($0.fret)" } ?? ""
        return "on \(prompt.stringLabel(in: tuning))\(fret)"
    }

    /// Seconds left before the timeout, and the fraction of the timeout used, while the prompt awaits an answer.
    var countdown: (remaining: Double, fraction: Double)? {
        guard let remaining = drill.timeRemaining(at: .seconds(now)) else { return nil }
        let timeout = NotePlayItDrill.timeout / .seconds(1)
        let left = remaining / .seconds(1)
        return (left, min(1, max(0, (timeout - left) / timeout)))
    }

    var stats: RunStats { RunStats(attempts: snapshot.attempts) }

    /// The last ~14 attempts for the strip under the flashcard, oldest first.
    var recentAttempts: [(id: Int, attempt: Attempt)] {
        let attempts = snapshot.attempts
        let start = max(0, attempts.count - 14)
        return (start..<attempts.count).map { ($0, attempts[$0]) }
    }
}

/// A played note with its onset on the drill clock (host seconds).
private struct HeardNote: Sendable {
    let pitch: Pitch
    let onset: Double
}

/// Moves stream times from one audio block onto the host clock that `AudioInputService.hostTimeNow()` uses.
private struct StreamClock {
    /// Host time minus stream time for this block.
    let offset: Double
    /// Host time of the end of the block: when its played notes were detected.
    let blockEnd: Double

    init(block: AudioInputBlock) {
        let streamEnd = block.streamTime + Double(block.samples.count) / block.sampleRate
        // Without a host time from Core Audio, take the block as just finished.
        offset = block.hostTime.map { $0 - block.streamTime } ?? (AudioInputService.hostTimeNow() - streamEnd)
        blockEnd = streamEnd + offset
    }

    func hostTime(ofStreamTime time: Double) -> Double { time + offset }
}
