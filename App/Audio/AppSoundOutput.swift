import AVFoundation
import Observation
import PracticeCore

/// The app's one sound output: tones and chimes through an output-only engine on the system default output, at the
/// system volume. Separate from the audio input: it never touches the engine's input node. AVAudioEngine still
/// makes its temporary aggregate, but only this app sees it, its input is never started, and input lists leave it out.
///
/// The engine runs from `prepare()` (or the first sound) to `release()`, and is made again when the default output
/// or its set-up changes.
@MainActor @Observable
final class AppSoundOutput {
    /// Why nothing can be heard; nil when sound works, as far as is known. Cleared by a change of output, or by
    /// preparing successfully.
    private(set) var problem: String?

    /// False when there is no output device at all. Otherwise, after a problem, preparing again may work.
    private(set) var hasDevice = true

    @ObservationIgnored private var engine: Engine?
    /// When the last chime has been heard.
    @ObservationIgnored private var chimeEnd: ContinuousClock.Instant = .now
    @ObservationIgnored private var lateRelease: Task<Void, Never>?
    @ObservationIgnored private var outputObserver: CoreAudioDevices.ChangeObserver?
    @ObservationIgnored private let isInert: Bool

    /// Inert (in `Snapshots`): makes no sound and touches no device, but says it plays, unless given a problem.
    init(isInert: Bool = false, problem: String? = nil) {
        self.isInert = isInert
        self.problem = problem
        hasDevice = problem == nil
        guard !isInert else { return }
        checkForOutput()
        outputObserver = CoreAudioDevices.observeDefaultOutput { [weak self] in self?.outputChanged() }
    }

    /// Starts the engine, so that the first sound isn't late. False, with a problem, if it can't.
    @discardableResult
    func prepare() -> Bool {
        if isInert { return problem == nil }
        lateRelease?.cancel()
        if let engine, engine.isRunning { return true }
        engine = nil
        checkForOutput()
        guard let device = CoreAudioDevices.defaultOutputID() else { return false }
        do {
            engine = try Engine(device: device) { [weak self] in self?.engineChanged($0) }
            return true
        } catch {
            problem = "Sound output couldn’t start (\((error as NSError).code))."
            return false
        }
    }

    /// Plays a sound now, over a chime but in place of any tones, and returns how long until it is heard. Nil, with
    /// a problem, if it can't.
    func play(_ sound: AppSound) -> Duration? {
        guard prepare() else { return nil }
        if isInert { return .zero }
        guard let engine else { return nil }
        engine.play(sound)
        let latency = Duration.seconds(engine.latency)
        if sound.isChime { chimeEnd = .now + latency + sound.duration }
        return latency
    }

    /// Cuts off any tones; a chime plays on.
    func stopTones() { engine?.stopTones() }

    /// Nothing more to play for now: cuts off any tones, and stops the engine once a chime has ended.
    func release() {
        lateRelease?.cancel()
        guard let engine, chimeEnd > .now else { return self.engine = nil }
        engine.stopTones()
        lateRelease = Task { [weak self, chimeEnd] in
            try? await Task.sleep(until: chimeEnd)
            if !Task.isCancelled { self?.engine = nil }
        }
    }

    private func checkForOutput() {
        hasDevice = CoreAudioDevices.defaultOutputID() != nil
        problem = hasDevice ? nil : "There’s no sound output device."
    }

    private func outputChanged() {
        checkForOutput()
        guard let engine else { return }
        if engine.device != CoreAudioDevices.defaultOutputID() { restart() }
    }

    /// The engine stops itself when the output's set-up changes, such as its sample rate.
    private func engineChanged(_ changed: Engine) {
        if changed === engine, !changed.isRunning { restart() }
    }

    private func restart() {
        engine = nil
        prepare()
    }

    /// One AVAudioEngine on one output; running from the start until it is released.
    @MainActor
    private final class Engine {
        let device: AudioDeviceID
        private let engine = AVAudioEngine()
        private let tones = AVAudioPlayerNode()
        private let chimes = AVAudioPlayerNode()
        private let format: AVAudioFormat
        private let changes = NoticeObserver()

        init(device: AudioDeviceID, onChange: @escaping @MainActor (Engine) -> Void) throws {
            self.device = device
            // The mixer converts to the device's rate.
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1) else {
                throw CocoaError(.featureUnsupported)
            }
            self.format = format
            for player in [tones, chimes] {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
            }
            try engine.start()
            tones.play()
            chimes.play()
            changes.observe(.AVAudioEngineConfigurationChange, object: engine) { [weak self] in
                if let self { onChange(self) }
            }
        }

        var isRunning: Bool { engine.isRunning }

        /// From a sound being scheduled to its being heard, in seconds.
        var latency: Double { max(0, engine.outputNode.presentationLatency) }

        func play(_ sound: AppSound) {
            let samples = AppSoundSynth.samples(of: sound, sampleRate: format.sampleRate)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { return }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            for (index, sample) in samples.enumerated() { channel[index] = sample }
            let player = sound.isChime ? chimes : tones
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !player.isPlaying { player.play() }
        }

        func stopTones() { tones.stop() }

        deinit { engine.stop() }
    }
}

/// A notification observer that ends when released.
private final class NoticeObserver {
    private var token: NSObjectProtocol?

    /// Calls `onNotice` on the main queue.
    func observe(_ name: Notification.Name, object: AnyObject, _ onNotice: @escaping @MainActor () -> Void) {
        token = NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { _ in
            MainActor.assumeIsolated { onNotice() }
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}
