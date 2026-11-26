import Foundation
import ListenCore
import Observation
import PracticeCore

/// The latency check in Settings › Audio: plays `LatencyCheck`'s clicks on the metronome, hears the notes played on
/// them, and stores the input delay it measures for the input device, in UserDefaults (the same store as
/// `@AppStorage`). Drills read it with `AudioInputSettings.inputDelay(ofDevice:)`.
@MainActor @Observable
final class LatencyCheckModel {
    enum Stage: Equatable {
        case idle
        /// On a device, until the check ends.
        case running(LatencyCheck, device: String)
        /// The last check heard too few notes; what was measured before stays.
        case tooFew(heard: Int)
    }

    private(set) var stage = Stage.idle
    /// What is under way, for the screen; nil before the count-in.
    private(set) var progress: LatencyCheck.Progress?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private weak var metronome: Metronome?
    @ObservationIgnored private let feed = PlayedNoteFeed()
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Touched when a delay is stored, so that the screen reads it again.
    private var stored = 0

    private static let interval: Duration = .milliseconds(50)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isRunning: Bool {
        if case .running = stage { true } else { false }
    }

    /// The device's, as last measured; nil if the check hasn't run on it.
    func inputDelay(ofDevice uid: String) -> Duration? {
        _ = stored
        return AudioInputSettings.measuredInputDelay(ofDevice: uid, in: defaults)
    }

    /// The consumer for `.listensToAudioInput(_:)`.
    var audioConsumer: AudioInputConsumer {
        feed.consumer { [weak self] notes in self?.heard(notes) }
    }

    /// Starts the clicks: a bar of count-in, then the eight to play on.
    func start(on device: AudioInputDevice, metronome: Metronome) {
        guard !isRunning, !metronome.isRunning else { return }
        self.metronome = metronome
        feed.reset()
        var check = LatencyCheck(start: Metronome.now)
        check.clicksStarted(metronome.start(check.track))
        metronome.stop(at: check.end)
        stage = .running(check, device: device.uid)
        progress = nil
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                if !Task.isCancelled { self?.tick() }
            }
        }
    }

    /// Stops a check that is going, keeping nothing from it.
    func stop() {
        guard isRunning else { return }
        metronome?.stop()
        end(.idle)
    }

    private func heard(_ notes: [HeardNote]) {
        guard case .running(var check, let device) = stage else { return }
        for note in notes { check.heard(onset: .seconds(note.onset)) }
        stage = .running(check, device: device)
    }

    private func tick() {
        guard case .running(let check, let device) = stage else { return }
        let now = Metronome.now
        progress = check.progress(at: now)
        guard now >= check.end else { return }
        switch check.result {
        case .measured(let delay):
            AudioInputSettings.store(inputDelay: delay, ofDevice: device, in: defaults)
            stored += 1
            end(.idle)
        case .tooFew(let heard):
            end(.tooFew(heard: heard))
        }
    }

    private func end(_ stage: Stage) {
        task?.cancel()
        task = nil
        progress = nil
        self.stage = stage
    }

    #if DEBUG
    /// Shows a check part way, or ended, without playing it (see `Snapshots`).
    func showForSnapshot(_ stage: Stage, progress: LatencyCheck.Progress? = nil) {
        self.stage = stage
        self.progress = progress
    }

    func storeForSnapshot(_ delay: Duration, ofDevice uid: String) {
        AudioInputSettings.store(inputDelay: delay, ofDevice: uid, in: defaults)
        stored += 1
    }
    #endif
}
