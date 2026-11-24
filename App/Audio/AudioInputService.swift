import AppKit
import AVFoundation
import ListenCore
import Observation

/// The app's audio input: lists input devices, remembers the chosen device and channel, and while at least one
/// listening screen is open runs an input unit (ADR 0004) that delivers the chosen channel's mono samples to
/// the attached consumers and drives the input meter.
///
/// One instance for the app, in the environment. Screens don't start and stop it directly; they use
/// `.listensToAudioInput(…)`, which counts them in on appear and out on disappear. The unit runs only while
/// that count is above zero (and microphone access is granted), so the mic-in-use indicator is off otherwise.
@MainActor @Observable
final class AudioInputService {
    /// Input devices only (output-only devices are left out), sorted by name.
    private(set) var devices: [AudioInputDevice] = []
    /// The device and channel being listened to; nil when there are no input devices.
    private(set) var choice: AudioInputChoice?
    private(set) var permission: AudioInputPermission
    /// True while the input unit runs (the mic-in-use indicator is on).
    private(set) var isRunning = false
    /// Input meter, 0–1 (−60…0 dBFS peak), with a short release. 0 when not running.
    private(set) var level = 0.0
    /// Why the input unit couldn't start, if it couldn't.
    private(set) var failure: String?

    var state: AudioInputState {
        AudioInputState(permission: permission, device: choice?.device, devices: devices, isRunning: isRunning)
    }

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
    @ObservationIgnored private var unit: AudioInputUnit?
    @ObservationIgnored private var startedSetup: InputSetup?
    @ObservationIgnored private var stream: AudioInputStream?
    @ObservationIgnored private var levelTask: Task<Void, Never>?
    @ObservationIgnored private var setupObserver: CoreAudioDevices.ChangeObserver?
    @ObservationIgnored private var deviceObserver: CoreAudioDevices.ChangeObserver?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var isRequestingPermission = false

    /// Requested block size: 512 frames ≈ 11 ms at 48 kHz, within the detection latency budget (ADR 0004).
    private static let bufferFrames: UInt32 = 512
    /// Meter release, in full scale per second.
    private static let meterRelease = 1.4

    /// True in `Snapshots`: lists devices and counts as granted, but never asks for access or starts the input unit.
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

    /// Counts a listening screen in, attaching its consumer (if any), and starts the input unit if needed.
    /// Prefer `.listensToAudioInput(…)`, which calls this and `stopListening` for you.
    func startListening(_ listener: UUID, consumer: AudioInputConsumer? = nil) {
        guard !isInert else { return }
        listeners.insert(listener)
        consumers.set(consumer, for: listener)
        permission = Self.currentPermission()
        refreshDevices()
        reconcile()
    }

    /// Counts a listening screen out and detaches its consumer; stops the input unit when none is left.
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

    // MARK: - Input unit lifecycle

    private func refreshDevices() {
        let listed = CoreAudioDevices.inputDevices()
        if listed != devices { devices = listed }
    }

    /// Brings the input unit in line with what is wanted: running on the current choice while any listening screen
    /// is open and access is granted, stopped otherwise.
    private func reconcile() {
        let resolved = AudioInputChoice.resolve(savedUID: savedDeviceUID, savedChannel: savedChannel,
                                                devices: devices, defaultUID: CoreAudioDevices.defaultInputUID())
        let choiceChanged = resolved != choice
        if choiceChanged { choice = resolved }

        let plan = AudioInputPlan(hasListeners: !listeners.isEmpty, permission: permission, hasChoice: choice != nil,
                                  choiceChanged: choiceChanged, isRunning: isRunning, hasTriedToStart: startedSetup != nil)
        if plan.asksForPermission { requestPermission() }
        switch plan.unit {
        case .leave: break
        case .restart: restartUnit()
        case .stop: stopUnit()
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

    private static func currentPermission() -> AudioInputPermission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    private func restartUnit() {
        stopUnit()
        guard let choice else { return }
        do {
            try startUnit(on: choice)
            failure = nil
        } catch {
            isRunning = false
            failure = error.localizedDescription
        }
    }

    /// A fresh input unit per run, on the device's own sample rate.
    private func startUnit(on choice: AudioInputChoice) throws(AudioInputError) {
        guard let deviceID = CoreAudioDevices.deviceID(forUID: choice.device.uid) else {
            throw .deviceUnavailable(choice.device.name)
        }
        // Watched even if starting fails, so a device that is still changing over is tried again when it settles.
        let setup = InputSetup(deviceID: deviceID)
        startedSetup = setup
        setupObserver = CoreAudioDevices.observeChanges(of: deviceID) { [weak self] in self?.setupMayHaveChanged() }
        guard setup.canStart else { throw .noInputChannels(choice.device.name) }

        let stream = AudioInputStream(consumers: consumers)
        let unit = try AudioInputUnit(setup: setup, deviceName: choice.device.name, channelIndex: choice.channel - 1,
                                      bufferFrames: Self.bufferFrames, onBlock: stream.process)
        self.stream = stream
        self.unit = unit
        isRunning = true

        levelTask = Task { [weak self] in
            var last = 0.0
            for await new in stream.levels {
                guard let self else { return }
                level = max(new.fraction, level - Self.meterRelease * (new.time - last))
                last = new.time
            }
        }
    }

    /// Starts again if the device's set-up is no longer the one tried last.
    private func setupMayHaveChanged() {
        guard let startedSetup else { return }
        refreshDevices()
        guard InputSetup.needsRestart(tried: startedSetup, now: InputSetup(deviceID: startedSetup.deviceID)) else { return }
        isRunning = false
        reconcile()
    }

    private func recheckPermission() {
        permission = Self.currentPermission()
        reconcile()
    }

    private func stopUnit() {
        setupObserver = nil
        startedSetup = nil
        unit?.stop()
        unit = nil
        stream?.finish()
        stream = nil
        levelTask?.cancel()
        levelTask = nil
        isRunning = false
        level = 0
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
        case .noInputUnit: "macOS has no audio input unit."
        case .couldNotSelectDevice(let name, let status): "Couldn't listen to \(name) (error \(status))."
        case .noInputChannels(let name): "\(name) reports no input channels."
        case .couldNotStart(let code): "Couldn't start audio input (error \(code))."
        }
    }
}
