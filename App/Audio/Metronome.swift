import Foundation
import Observation
import PracticeCore

/// The app's one metronome: plays a click track on the app's sound output, at the volume in Settings.
///
/// Every time here is when a click is heard, on the clock of `AudioInputService.hostTimeNow()`; clicks are sent to
/// the output early by its latency. They are scheduled about a second ahead, each at its own time, so they don't
/// drift and a busy main thread doesn't hold them up. With no output, or sound off, the beats still go on, to be seen.
/// Clicks are not registered with `AppSoundFilter`.
///
/// Losing the output is for whoever started the clicks to notice (`AppSoundOutput.problem`). A change of output goes
/// on with the same clicks.
@MainActor @Observable
final class Metronome {
    /// Whether clicks are going, or about to.
    private(set) var isRunning = false

    /// Whether they were started by Listen in Settings.
    private(set) var isListening = false

    /// Listen's tempo.
    static let listenBPM = 60

    @ObservationIgnored private var schedule = ClickSchedule()
    @ObservationIgnored private let output: AppSoundOutput
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?

    private static let ahead: Duration = .seconds(1)
    private static let interval: Duration = .milliseconds(200)
    /// The least time from asking for clicks to the first being sent to the output.
    private static let lead: Duration = .milliseconds(80)

    init(output: AppSoundOutput, defaults: UserDefaults = .standard) {
        self.output = output
        self.defaults = defaults
    }

    /// The time signature and emphasis in Settings.
    var meter: Meter { MetronomeSettings.meters(in: defaults).meter }

    /// A scale drill's remembered tempo, Hold and ladder, in sessions and free practice alike, put in place of the settings' own.
    func loadTempo(of kind: DrillKind, into settings: inout PassSettings) {
        settings.tempo = defaults.object(forKey: MetronomeSettings.Key.tempo(of: kind)) as? Int ?? PassSettings().tempo
        settings.holdsTempo = defaults.bool(forKey: MetronomeSettings.Key.holdsTempo(of: kind))
        settings.ladder = TempoLadder(notClean: defaults.integer(forKey: MetronomeSettings.Key.notClean(of: kind)))
    }

    func storeTempo(of kind: DrillKind, from settings: PassSettings) {
        defaults.set(settings.tempo, forKey: MetronomeSettings.Key.tempo(of: kind))
        defaults.set(settings.holdsTempo, forKey: MetronomeSettings.Key.holdsTempo(of: kind))
        defaults.set(settings.ladder.notClean, forKey: MetronomeSettings.Key.notClean(of: kind))
    }

    /// Does what a drill asks, and tells it when the clicks will be heard.
    func perform(_ requests: [ClickRequest], heard: (ClickTrack) -> Void) {
        for request in requests {
            switch request {
            case .start(let track): heard(start(track))
            case .stop(let time): stop(at: time)
            }
        }
    }

    /// Plays a track from its start on, in place of any other clicks from then on, until stopped. Returns it as it
    /// will be heard: later than asked if its start is too soon to play. Asking in time follows on with no gap.
    @discardableResult
    func start(_ track: ClickTrack) -> ClickTrack {
        isListening = false
        output.clickVolume = MetronomeSettings.clickVolume(in: defaults)
        let latency = output.startClicks() ?? .zero
        let heard = ClickTrack(meter: track.meter, bpm: track.bpm, start: max(track.start, Self.now + latency + Self.lead))
        schedule.start(heard)
        output.cancelClicks(from: heard.start)
        isRunning = true
        playOn()
        if task == nil {
            task = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.interval)
                    if !Task.isCancelled { self?.playOn() }
                }
            }
        }
        return heard
    }

    /// No clicks at or after a time, such as a click's in the track; now if nil.
    func stop(at time: Duration? = nil) {
        let time = time ?? Self.now
        schedule.stop(at: time)
        output.cancelClicks(from: time)
        playOn()
    }

    /// The last click heard by a time; nil before the first, and once they have stopped.
    func current(at time: Duration) -> ScheduledClick? { schedule.current(at: time) }

    static var now: Duration { .seconds(AudioInputService.hostTimeNow()) }

    /// Schedules the next second's clicks.
    private func playOn() {
        let now = Self.now
        guard !schedule.isOver(at: now) else { return finish() }
        schedule.forget(before: now)
        output.clickVolume = MetronomeSettings.clickVolume(in: defaults)
        output.schedule(schedule.clicks(from: now, before: now + Self.ahead))
    }

    private func finish() {
        task?.cancel()
        task = nil
        guard isRunning else { return }
        output.endClicks()
        isRunning = false
        isListening = false
    }

    // MARK: - Listen

    /// Plays the meter in Settings, from beat 1. Does nothing while a drill has the click.
    func listen() {
        guard isListening || !isRunning else { return }
        start(ClickTrack(meter: meter, bpm: Self.listenBPM, start: Self.now))
        isListening = true
    }

    func stopListening() {
        if isListening { stop() }
    }
}
