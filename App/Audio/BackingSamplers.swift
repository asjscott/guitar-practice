import AVFoundation
import PracticeCore

/// Where the backing's SoundFont is: the git-ignored `Sounds/` at the top of the checkout the app was built from,
/// filled by `scripts/fetch-sounds` (ADR 0006). The app runs from Xcode, so the source's own path finds it.
enum BackingSounds {
    static let fetchHint = "Run scripts/fetch-sounds in the project folder to fetch the backing’s sounds."

    static var soundFont: URL? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sounds/FluidR3_GM.sf2")
        return FileManager.default.isReadableFile(atPath: url.path) ? url : nil
    }

    /// The General MIDI preset for each part: fingered bass, electric piano and the standard kit.
    static func preset(of part: BackingPart) -> (program: UInt8, bankMSB: UInt8) {
        switch part {
        case .bass: (33, UInt8(kAUSampler_DefaultMelodicBankMSB))
        case .keys: (4, UInt8(kAUSampler_DefaultMelodicBankMSB))
        case .drums: (0, UInt8(kAUSampler_DefaultPercussionBankMSB))
        }
    }
}

/// The backing's samplers, one per part, on the output engine, and what feeds them their notes.
///
/// A sampler takes MIDI events at sample times of its own, and those it has been given can't be taken back. So notes
/// are handed to it only shortly before they are due, from a timer off the main thread, by mapping host time to its
/// sample time; until then they wait here and can be cancelled. Cancelling mutes what was already handed over.
/// Thread-safe: the main actor adds and cancels notes, the timer's queue hands them over.
final class BackingSamplers: @unchecked Sendable {
    private struct Event {
        let part: BackingPart
        let bytes: (UInt8, UInt8, UInt8)
        /// When it is heard; notes can be cancelled from a time on.
        let heard: Duration
        /// When it is sent to the output, in host seconds: heard less the output's latency.
        let due: Double
    }

    private let samplers: [BackingPart: AVAudioUnitSampler]
    private let midi: [BackingPart: AUScheduleMIDIEventBlock]
    private let lock = NSLock()
    /// In order of `due`.
    private var waiting: [Event] = []
    /// The latest `due` handed to a sampler.
    private var handedOverUntil = -Double.infinity
    private let timer: DispatchSourceTimer
    private let queue = DispatchQueue(label: "GuitarPractice.backing", qos: .userInteractive)

    /// How long before it is due a note is handed over.
    private static let horizon = 0.04
    private static let tick = DispatchTimeInterval.milliseconds(5)
    /// Notes later than this are left out rather than played late.
    private static let tooLate = 0.005
    /// General MIDI's default channel volume.
    private static let channelVolume: UInt8 = 100

    /// Attaches the samplers to a running engine's mixer and loads their presets; nil if the SoundFont can't be loaded.
    @MainActor
    init?(soundFont: URL, on engine: AVAudioEngine) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2) else { return nil }
        var samplers: [BackingPart: AVAudioUnitSampler] = [:]
        var midi: [BackingPart: AUScheduleMIDIEventBlock] = [:]
        for part in BackingPart.allCases {
            let sampler = AVAudioUnitSampler()
            engine.attach(sampler)
            // At 48 kHz, so that its sample times run at the rate they are worked out at.
            engine.connect(sampler, to: engine.mainMixerNode, format: format)
            let preset = BackingSounds.preset(of: part)
            do {
                try sampler.loadSoundBankInstrument(at: soundFont, program: preset.program, bankMSB: preset.bankMSB, bankLSB: 0)
            } catch {
                for sampler in samplers.values + [sampler] { engine.detach(sampler) }
                return nil
            }
            guard let block = sampler.auAudioUnit.scheduleMIDIEventBlock else { return nil }
            samplers[part] = sampler
            midi[part] = block
        }
        self.samplers = samplers
        self.midi = midi
        // So that the volume put back after muting is the one it starts at.
        waiting = BackingPart.allCases.map { part in
            Event(part: part, bytes: (0xB0, 7, Self.channelVolume), heard: .seconds(-1_000_000), due: 0)
        }
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.tick, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.handOver() }
        timer.resume()
    }

    deinit { timer.cancel() }

    /// Detaches the samplers.
    @MainActor
    func detach(from engine: AVAudioEngine) {
        timer.cancel()
        for sampler in samplers.values { engine.detach(sampler) }
    }

    /// Adds notes to be heard at their times, given the output's latency. Each note is to be added once.
    func schedule(_ notes: [BackingNote], latency: Duration) {
        let latency = latency / .seconds(1)
        lock.lock()
        defer { lock.unlock() }
        for note in notes {
            let pitch = UInt8(clamping: note.pitch.midi), velocity = UInt8(clamping: note.velocity)
            waiting.append(Event(part: note.part, bytes: (0x90, pitch, velocity), heard: note.time,
                                 due: note.time / .seconds(1) - latency))
            waiting.append(Event(part: note.part, bytes: (0x80, pitch, 0), heard: note.time,
                                 due: (note.time + note.length) / .seconds(1) - latency))
        }
        waiting.sort { $0.due < $1.due }
    }

    /// No notes heard at or after a time. Those already handed over are muted from then until they are over.
    func cancel(from time: Duration, latency: Duration) {
        let now = Self.now
        let from = max(now, time / .seconds(1) - latency / .seconds(1))
        lock.lock()
        defer { lock.unlock() }
        waiting.removeAll { $0.heard >= time }
        // Note-offs of notes begun before then stay, so they still end.
        guard handedOverUntil > from else { return }
        for part in BackingPart.allCases {
            send(controller: 7, value: 0, to: part, at: from)
            send(controller: 120, value: 0, to: part, at: from)
            send(controller: 120, value: 0, to: part, at: handedOverUntil + 0.001)
            send(controller: 7, value: Self.channelVolume, to: part, at: handedOverUntil + 0.001)
        }
    }

    // MARK: On the timer's queue

    private static var now: Double { AVAudioTime.seconds(forHostTime: mach_absolute_time()) }

    private func handOver() {
        let now = Self.now
        lock.lock()
        defer { lock.unlock() }
        var handled = 0
        defer { waiting.removeFirst(handled) }
        for event in waiting {
            guard event.due < now + Self.horizon else { return }
            let isNoteOn = event.bytes.0 & 0xF0 == 0x90
            // Too late for a note-on: left out. A late note-off still ends its note.
            if !isNoteOn || event.due >= now - Self.tooLate {
                guard send(event.bytes, to: event.part, at: max(event.due, now)) else { return }
                handedOverUntil = max(handedOverUntil, event.due)
            }
            handled += 1
        }
    }

    private func send(controller: UInt8, value: UInt8, to part: BackingPart, at time: Double) {
        send((0xB0, controller, value), to: part, at: time)
    }

    /// False until the sampler has rendered, so that its sample time is known.
    @discardableResult
    private func send(_ bytes: (UInt8, UInt8, UInt8), to part: BackingPart, at time: Double) -> Bool {
        guard let sampler = samplers[part], let block = midi[part], let rendered = sampler.lastRenderTime,
              rendered.isSampleTimeValid, rendered.isHostTimeValid else { return false }
        let offset = (time - AVAudioTime.seconds(forHostTime: rendered.hostTime)) * rendered.sampleRate
        let sampleTime = rendered.sampleTime + AVAudioFramePosition(offset.rounded())
        var message = [bytes.0, bytes.1, bytes.2]
        block(AUEventSampleTime(sampleTime), 0, 3, &message)
        return true
    }
}
