import AppKit
import AVFoundation
import Observation

/// The app's audio input: lists input devices, remembers the chosen device and channel, and while at least one
/// listening screen is open runs an AVAudioEngine input tap that delivers the chosen channel's mono samples to
/// the attached consumers and drives the input meter.
///
/// One instance for the app, in the environment. Screens don't start and stop it directly; they use
/// `.listensToAudioInput(…)`, which counts them in on appear and out on disappear. The engine runs only while
/// that count is above zero (and microphone access is granted), so the mic-in-use indicator is off otherwise.
@MainActor @Observable
final class AudioInputService {
    enum Permission: Equatable {
        case undetermined, granted, denied
    }

    /// Input devices only (output-only devices are left out), sorted by name.
    private(set) var devices: [AudioInputDevice] = []
    /// The device and channel being listened to; nil when there are no input devices.
    private(set) var choice: AudioInputChoice?
    private(set) var permission: Permission
    /// True while the engine runs (the mic-in-use indicator is on).
    private(set) var isRunning = false
    /// Input meter, 0–1 (−60…0 dBFS peak), with a short release. 0 when not running.
    private(set) var level = 0.0
    /// Why the engine couldn't start, if it couldn't.
    private(set) var failure: String?

    /// False while microphone access is denied or there's no input device: nothing can be heard, so a
    /// listening exercise shouldn't start.
    var canListen: Bool { permission != .denied && choice != nil }

    /// Shown when the saved device isn't connected and the system default stands in.
    var fallbackNotice: String? {
        guard let choice, choice.isFallback else { return nil }
        let saved = savedDeviceName.isEmpty ? "Your audio interface" : savedDeviceName
        return "\(saved) isn't connected. Using the system default input, \(choice.device.name)."
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var savedDeviceUID: String
    @ObservationIgnored private var savedDeviceName: String
    @ObservationIgnored private var savedChannel: Int

    @ObservationIgnored private var listeners = Set<UUID>()
    @ObservationIgnored private let consumers = AudioInputConsumers()
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var startedSetup: InputSetup?
    @ObservationIgnored private var tap: AudioInputTap?
    @ObservationIgnored private var levelTask: Task<Void, Never>?
    @ObservationIgnored private var configurationObserver: NSObjectProtocol?
    @ObservationIgnored private var deviceObserver: CoreAudioDevices.ChangeObserver?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var isRequestingPermission = false

    /// Requested tap size: 1024 frames ≈ 21 ms at 48 kHz, small enough for the detection latency budget.
    private static let bufferSize: AVAudioFrameCount = 1024
    /// Meter release per block (≈ 1.4 full scale per second at 48 kHz / 1024).
    private static let meterRelease = 0.03

    /// True in `Snapshots`: lists devices and counts as granted, but never asks for access or starts the engine.
    @ObservationIgnored private let isInert: Bool

    init(defaults: UserDefaults = .standard, isInert: Bool = false) {
        self.defaults = defaults
        self.isInert = isInert
        AudioInputSettings.forgetTemporaryDevice(in: defaults)
        savedDeviceUID = defaults.string(forKey: AudioInputSettings.Key.deviceUID) ?? AudioInputSettings.defaultDeviceUID
        savedDeviceName = defaults.string(forKey: AudioInputSettings.Key.deviceName) ?? ""
        savedChannel = defaults.object(forKey: AudioInputSettings.Key.channel) as? Int ?? AudioInputSettings.defaultChannel
        permission = isInert ? .granted : Self.currentPermission()

        refreshDevices()
        if isInert {
            reconcile()     // no listeners, so this only resolves the choice
            return
        }
        deviceObserver = CoreAudioDevices.observeChanges { [weak self] in
            self?.refreshDevices()
            self?.reconcile()
        }
        // Access may have been granted in System Settings while the app was in the background.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheckPermission() }
        }
    }

    // MARK: - Listening screens and consumers

    /// Counts a listening screen in, attaching its consumer (if any), and starts the engine if needed.
    /// Prefer `.listensToAudioInput(…)`, which calls this and `stopListening` for you.
    func startListening(_ listener: UUID, consumer: AudioInputConsumer? = nil) {
        guard !isInert else { return }
        listeners.insert(listener)
        consumers.set(consumer, for: listener)
        permission = Self.currentPermission()
        refreshDevices()
        reconcile()
    }

    /// Counts a listening screen out and detaches its consumer; stops the engine when none is left.
    func stopListening(_ listener: UUID) {
        listeners.remove(listener)
        consumers.set(nil, for: listener)
        reconcile()
    }

    // MARK: - Choosing the input

    /// Saves the device (by UID) and switches to it.
    func selectDevice(_ device: AudioInputDevice) {
        savedDeviceUID = device.uid
        savedDeviceName = device.name
        defaults.set(device.uid, forKey: AudioInputSettings.Key.deviceUID)
        defaults.set(device.name, forKey: AudioInputSettings.Key.deviceName)
        reconcile()
    }

    /// Saves the 1-based channel and switches to it.
    func selectChannel(_ channel: Int) {
        savedChannel = channel
        defaults.set(channel, forKey: AudioInputSettings.Key.channel)
        reconcile()
    }

    /// Opens System Settings › Privacy & Security › Microphone.
    func openMicrophonePrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Now, in seconds, on the same clock as `AudioInputBlock.hostTime`.
    nonisolated static func hostTimeNow() -> Double {
        AVAudioTime.seconds(forHostTime: mach_absolute_time())
    }

    // MARK: - Engine lifecycle

    private func refreshDevices() {
        let listed = CoreAudioDevices.inputDevices()
        if listed != devices { devices = listed }
    }

    /// Brings the engine in line with what is wanted: running on the current choice while any listening screen
    /// is open and access is granted, stopped otherwise.
    private func reconcile() {
        let resolved = AudioInputChoice.resolve(savedUID: savedDeviceUID, savedChannel: savedChannel,
                                                devices: devices, defaultUID: CoreAudioDevices.defaultInputUID())
        let choiceChanged = resolved != choice
        if choiceChanged { choice = resolved }

        if !listeners.isEmpty, permission == .undetermined {
            requestPermission()
        }
        let wanted = !listeners.isEmpty && permission == .granted && choice != nil
        if wanted, !isRunning || choiceChanged {
            restartEngine()
        } else if !wanted, engine != nil {
            stopEngine()
        }
    }

    private func requestPermission() {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            isRequestingPermission = false
            permission = Self.currentPermission()
            reconcile()
        }
    }

    private static func currentPermission() -> Permission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    private func restartEngine() {
        stopEngine()
        guard let choice else { return }
        do {
            try startEngine(on: choice)
            failure = nil
        } catch {
            stopEngine()
            failure = error.localizedDescription
        }
    }

    /// A fresh engine per run: set the device on the input node, tap the device's own format, start.
    private func startEngine(on choice: AudioInputChoice) throws(AudioInputError) {
        guard let deviceID = CoreAudioDevices.deviceID(forUID: choice.device.uid) else {
            throw .deviceUnavailable(choice.device.name)
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        guard let unit = input.audioUnit else { throw .noInputUnit }
        var id = deviceID
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw .couldNotSelectDevice(choice.device.name, status) }

        // Not outputFormat: that still describes the default device, and a tap with the wrong rate hears nothing.
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw .noInputChannels(choice.device.name) }

        let tap = AudioInputTap(channelIndex: choice.channel - 1, consumers: consumers)
        tap.install(on: input, format: format, bufferSize: Self.bufferSize)
        self.engine = engine
        self.tap = tap
        startedSetup = InputSetup(of: engine)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw .couldNotStart((error as NSError).code)
        }
        isRunning = true

        levelTask = Task { [weak self] in
            for await fraction in tap.levels {
                guard let self else { return }
                level = max(fraction, level - Self.meterRelease)
            }
        }
        // The engine stops itself when the device's format or routing changes; see engineConfigurationChanged.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.engineConfigurationChanged() }
        }
    }

    /// Starts again on the new setup, unless the engine is still running on the device and format it was started
    /// with. Selecting a device on the input node also posts this notice; restarting then selects the device again,
    /// posts again, and loops before any audio is delivered (#20).
    private func engineConfigurationChanged() {
        guard let engine else { return }
        refreshDevices()
        if engine.isRunning, InputSetup(of: engine) == startedSetup { return }
        isRunning = false
        reconcile()
    }

    private func recheckPermission() {
        permission = Self.currentPermission()
        reconcile()
    }

    private func stopEngine() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        startedSetup = nil
        tap?.finish()
        tap = nil
        levelTask?.cancel()
        levelTask = nil
        isRunning = false
        level = 0
    }
}

/// What an engine's input node listens to: compared to tell a real configuration change from a repeat notice.
private struct InputSetup: Equatable {
    var deviceID: AudioDeviceID
    var format: AVAudioFormat

    init(of engine: AVAudioEngine) {
        deviceID = engine.inputNode.auAudioUnit.deviceID
        format = engine.inputNode.inputFormat(forBus: 0)
    }
}

enum AudioInputError: LocalizedError {
    case deviceUnavailable(String)
    case noInputUnit
    case couldNotSelectDevice(String, OSStatus)
    case noInputChannels(String)
    case couldNotStart(Int)

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable(let name): "\(name) isn't available."
        case .noInputUnit: "The audio engine has no input."
        case .couldNotSelectDevice(let name, let status): "Couldn't listen to \(name) (error \(status))."
        case .noInputChannels(let name): "\(name) reports no input channels."
        case .couldNotStart(let code): "Couldn't start audio input (error \(code))."
        }
    }
}
