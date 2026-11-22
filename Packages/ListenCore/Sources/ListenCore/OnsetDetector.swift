import Foundation

/// Finds onsets: moments the sound starts or jumps louder (a new pluck).
/// Fed one sample at a time, so onsets land on the exact sample.
///
/// A peak envelope (instant attack, 50 ms release) is compared with its
/// highest value over the last 25 ms. An onset is the envelope rising through
/// the gate from below, or rising 3 dB above that recent high. A decaying
/// tail never rises, so it never makes an onset. After an onset there is none
/// for 50 ms, so one attack gives one onset.
struct OnsetDetector: Sendable {
    private let gate: Float
    private let release: Float
    private let rise: Float = 1.413          // 3 dB in amplitude
    private let frameLength: Int
    private let refractory: Double = 0.05
    private var envelope: Float = 0
    /// Envelope at the end of each recent frame, newest last.
    private var history: [Float]
    private var historyIndex = 0
    private var samplesInFrame = 0
    private var triggerLevel: Float
    private var quietUntil = -Double.infinity

    /// - Parameters:
    ///   - sampleRate: in Hz.
    ///   - gate: the noise gate in dBFS; quieter sound never makes an onset.
    init(sampleRate: Double, gate: Double) {
        self.gate = Float(pow(10, gate / 20))
        release = Float(exp(-1 / (0.05 * sampleRate)))
        frameLength = max(1, Int(sampleRate / 750))           // about 1.3 ms
        history = [Float](repeating: 0, count: max(1, Int(0.025 * sampleRate) / frameLength))
        triggerLevel = self.gate
    }

    /// Feeds one sample at stream time `time`; returns true if an onset is at this sample.
    mutating func add(_ sample: Float, time: Double) -> Bool {
        envelope = max(abs(sample), envelope * release)
        var onset = false
        if envelope >= triggerLevel, time >= quietUntil {
            onset = true
            quietUntil = time + refractory
        }
        samplesInFrame += 1
        if samplesInFrame == frameLength {
            samplesInFrame = 0
            history[historyIndex] = envelope
            historyIndex = (historyIndex + 1) % history.count
            let recentHigh = history.max() ?? 0
            triggerLevel = recentHigh < gate ? gate : recentHigh * rise
        }
        return onset
    }
}
