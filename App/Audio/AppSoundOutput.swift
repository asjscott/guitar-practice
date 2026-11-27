import AVFoundation
import ListenCore
import Observation
import PracticeCore

/// The app's one sound output: tones, chimes and clicks through an output-only engine on the system default output, at the
/// system volume. Separate from the audio input: it never touches the engine's input node. AVAudioEngine still
/// makes its temporary aggregate, but only this app sees it, its input is never started, and input lists leave it out.
///
/// The engine runs from `prepare()` (or the first sound) to `release()`, and while there are clicks, and is made again when the default output
/// or its set-up changes.
@MainActor @Observable
final class AppSoundOutput {
    /// Why nothing can be heard; nil when sound works, as far as is known. Cleared by a change of output, or by
    /// preparing successfully.
    private(set) var problem: String?

    /// False when there is no output device at all. Otherwise, after a problem, preparing again may work.
    private(set) var hasDevice = true

    /// How loud clicks are, 0–1.
    @ObservationIgnored var clickVolume: Float = 1 {
        didSet { if clickVolume != oldValue { engine?.clickVolume = clickVolume } }
    }

    @ObservationIgnored private var engine: Engine?
    /// Whether tones or chimes may follow: from `prepare()` to `release()`.
    @ObservationIgnored private var isPrepared = false
    /// From `startClicks()` to `endClicks()`.
    @ObservationIgnored private var hasClicks = false
    /// When the last chime has been heard.
    @ObservationIgnored private var chimeEnd: ContinuousClock.Instant = .now
    @ObservationIgnored private var lateRelease: Task<Void, Never>?
    @ObservationIgnored private var outputObserver: CoreAudioDevices.ChangeObserver?
    @ObservationIgnored private let isInert: Bool

    /// The backing's SoundFont, if it has been fetched (`scripts/fetch-sounds`).
    let backingSoundFont: URL?

    /// From `startBacking()` to `endBacking()`.
    @ObservationIgnored private var hasBacking = false

    /// Inert (in `Snapshots`): makes no sound and touches no device, but says it plays, unless given a problem, and
    /// has the backing's sounds unless told not to.
    init(isInert: Bool = false, problem: String? = nil, hasBackingSounds: Bool = true) {
        self.isInert = isInert
        self.problem = problem
        backingSoundFont = isInert ? (hasBackingSounds ? URL(fileURLWithPath: "/dev/null") : nil) : BackingSounds.soundFont
        hasDevice = problem == nil
        guard !isInert else { return }
        checkForOutput()
        outputObserver = CoreAudioDevices.observeDefaultOutput { [weak self] in self?.outputChanged() }
    }

    /// Starts the engine, so that the first sound isn't late. False, with a problem, if it can't.
    @discardableResult
    func prepare() -> Bool {
        isPrepared = true
        return startEngine()
    }

    private func startEngine() -> Bool {
        if isInert { return problem == nil }
        lateRelease?.cancel()
        if let engine, engine.isRunning { return true }
        engine = nil
        checkForOutput()
        guard let device = CoreAudioDevices.defaultOutputID() else { return false }
        do {
            let engine = try Engine(device: device) { [weak self] in self?.engineChanged($0) }
            engine.clickVolume = clickVolume
            self.engine = engine
            // Notes already scheduled on an engine before are lost; the backing goes on with those after.
            if hasBacking, let backingSoundFont { engine.loadBacking(from: backingSoundFont) }
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

    /// Nothing more to play for now: cuts off any tones, and stops the engine once a chime has ended, unless there
    /// are clicks.
    func release() {
        isPrepared = false
        engine?.stopTones()
        stopIdleEngine()
    }

    private func stopIdleEngine() {
        lateRelease?.cancel()
        guard !isPrepared, !hasClicks, !hasBacking else { return }
        guard chimeEnd > .now else { return engine = nil }
        lateRelease = Task { [weak self, chimeEnd] in
            try? await Task.sleep(until: chimeEnd)
            if !Task.isCancelled { self?.stopIdleEngine() }
        }
    }

    // MARK: - Clicks (for `Metronome`)

    /// Keeps the engine going for clicks. How long one takes to be heard; nil, with a problem, if it can't be.
    func startClicks() -> Duration? {
        hasClicks = true
        guard startEngine() else { return nil }
        return .seconds(engine?.latency ?? 0)
    }

    /// Schedules the clicks that aren't scheduled yet, so each is heard at its time (host time). Those it is too
    /// late for are left out, as are all of them while there is no output.
    func schedule(_ clicks: [ScheduledClick]) { engine?.schedule(clicks) }

    /// Drops scheduled clicks at or after a time; a click being heard rings on.
    func cancelClicks(from time: Duration) { engine?.cancelClicks(from: time) }

    func endClicks() {
        cancelClicks(from: .zero)
        hasClicks = false
        stopIdleEngine()
    }

    // MARK: - Backing (for `BackingPlayer`)

    /// Keeps the engine going for backing, with its samplers loaded. How long a note takes to be heard; nil if it
    /// can't be, with a problem if there's no output.
    func startBacking() -> Duration? {
        guard let backingSoundFont else { return nil }
        hasBacking = true
        guard startEngine() else { return nil }
        if isInert { return .zero }
        guard let engine, engine.loadBacking(from: backingSoundFont) else { return nil }
        return .seconds(engine.latency)
    }

    /// Schedules notes to be heard at their times (host time), each once. Left out while there is no output.
    func schedule(_ notes: [BackingNote]) { engine?.scheduleBacking(notes) }

    /// No backing heard at or after a time; what is sounding then stops.
    func cancelBacking(from time: Duration) { engine?.cancelBacking(from: time) }

    func endBacking() {
        cancelBacking(from: .zero)
        hasBacking = false
        stopIdleEngine()
    }

    private func checkForOutput() {
        hasDevice = CoreAudioDevices.defaultOutputID() != nil
        problem = hasDevice ? nil : "There’s no sound output device."
    }

    private func outputChanged() {
        checkForOutput()
        if let engine {
            if engine.device != CoreAudioDevices.defaultOutputID() { restart() }
        } else if isPrepared || hasClicks || hasBacking {
            // Back after none. Clicks go on in time: the metronome schedules them whether or not they can be heard.
            _ = startEngine()
        }
    }

    /// The engine stops itself when the output's set-up changes, such as its sample rate.
    private func engineChanged(_ changed: Engine) {
        if changed === engine, !changed.isRunning { restart() }
    }

    private func restart() {
        engine = nil
        _ = startEngine()
    }

    /// One AVAudioEngine on one output; running from the start until it is released.
    @MainActor
    private final class Engine {
        let device: AudioDeviceID
        private let runningEngine = StoppedOnRelease()
        private var engine: AVAudioEngine { runningEngine.engine }
        private let tones = AVAudioPlayerNode()
        private let chimes = AVAudioPlayerNode()
        private var clickSlots: [ClickSlot]
        private let clickSounds: (normal: AVAudioPCMBuffer, emphasised: AVAudioPCMBuffer)
        private let format: AVAudioFormat
        private let changes = NoticeObserver()

        init(device: AudioDeviceID, onChange: @escaping @MainActor (Engine) -> Void) throws {
            self.device = device
            // The mixer converts to the device's rate.
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1),
                  let normal = Self.buffer(of: Click.samples(emphasised: false, sampleRate: 48_000), format: format),
                  let emphasised = Self.buffer(of: Click.samples(emphasised: true, sampleRate: 48_000), format: format) else {
                throw CocoaError(.featureUnsupported)
            }
            self.format = format
            clickSounds = (normal, emphasised)
            clickSlots = (0..<Self.clickSlotCount).map { _ in ClickSlot() }
            let players = [tones, chimes] + clickSlots.map(\.player)
            for player in players {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
            }
            try engine.start()
            for player in players { player.play() }
            changes.observe(.AVAudioEngineConfigurationChange, object: engine) { [weak self] in
                if let self { onChange(self) }
            }
        }

        var isRunning: Bool { engine.isRunning }

        /// From a sound being scheduled to its being heard, in seconds.
        var latency: Double { max(0, engine.outputNode.presentationLatency) }

        func play(_ sound: AppSound) {
            let samples = AppSoundSynth.samples(of: sound, sampleRate: format.sampleRate)
            guard let buffer = Self.buffer(of: samples, format: format) else { return }
            let player = sound.isChime ? chimes : tones
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !player.isPlaying { player.play() }
        }

        func stopTones() { tones.stop() }

        private static func buffer(of samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { return nil }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            for (index, sample) in samples.enumerated() { channel[index] = sample }
            return buffer
        }

        // MARK: Clicks

        /// More than the second scheduled ahead holds at 160 BPM, with one ringing.
        private static let clickSlotCount = 6
        /// Longer than a click rings.
        private static let clickLength: Duration = .milliseconds(100)
        /// The least time ahead a click can be scheduled.
        private static let clickLead: Duration = .milliseconds(20)

        /// A player for one click at a time, so that one can be cancelled without the rest.
        private struct ClickSlot {
            let player = AVAudioPlayerNode()
            /// When its click is heard; nil if it has none.
            var time: Duration?
        }

        var clickVolume: Float = 1 {
            didSet { for slot in clickSlots { slot.player.volume = clickVolume } }
        }

        func schedule(_ clicks: [ScheduledClick]) {
            guard engine.isRunning else { return }
            let latency = Duration.seconds(latency), now = Metronome.now
            for click in clicks where click.time - latency >= now + Self.clickLead {
                guard !clickSlots.contains(where: { $0.time == click.time }) else { continue }
                guard let index = clickSlots.firstIndex(where: { slot in
                    slot.time.map { $0 + Self.clickLength < now } ?? true
                }) else { return }
                clickSlots[index].time = click.time
                let sound = click.isEmphasised ? clickSounds.emphasised : clickSounds.normal
                let hostTime = AVAudioTime.hostTime(forSeconds: (click.time - latency) / .seconds(1))
                clickSlots[index].player.scheduleBuffer(sound, at: AVAudioTime(hostTime: hostTime))
            }
        }

        // MARK: Backing

        /// Nil until loaded. Not registered with `AppSoundFilter`, like clicks.
        private var backing: BackingSamplers?

        /// Loads the samplers if they aren't yet; false if they can't be.
        @discardableResult
        func loadBacking(from soundFont: URL) -> Bool {
            if backing == nil { backing = BackingSamplers(soundFont: soundFont, on: engine) }
            return backing != nil
        }

        func scheduleBacking(_ notes: [BackingNote]) {
            guard engine.isRunning else { return }
            backing?.schedule(notes, latency: .seconds(latency))
        }

        func cancelBacking(from time: Duration) {
            backing?.cancel(from: time, latency: .seconds(latency))
        }

        func cancelClicks(from time: Duration) {
            let latency = Duration.seconds(latency), now = Metronome.now
            for index in clickSlots.indices {
                guard let click = clickSlots[index].time, click >= time, click - latency > now else { continue }
                clickSlots[index].time = nil
                clickSlots[index].player.stop()
                if engine.isRunning { clickSlots[index].player.play() }
            }
        }
    }
}

/// An audio engine that stops when this is released. On no actor, so that its deinit may use the engine.
private final class StoppedOnRelease {
    let engine = AVAudioEngine()

    deinit { engine.stop() }
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
