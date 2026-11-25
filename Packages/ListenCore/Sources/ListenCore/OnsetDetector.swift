import Foundation

/// Finds moments that may be onsets: places where the sound starts, jumps louder or gains highs. Fed one sample at a
/// time, so they land on the exact sample. It is generous on purpose: a click, a fret noise or a note swelling makes
/// a candidate too, and the note tracker decides which began a played note (ADR 0005).
struct OnsetDetector: Sendable {
    /// A moment that may be an onset.
    struct Candidate: Sendable, Equatable {
        let time: Double
        /// The level jumped by 3 dB, or rose through the gate. Otherwise it is only a small rise, or new highs.
        let isStrong: Bool
        /// The highs jumped by 6 dB, as a pick makes them.
        let isBrighter: Bool
    }

    private var level: RiseDetector
    private var highs: RiseDetector
    private var highPass: Butterworth
    /// Weak candidates closer to the last one than this are dropped: one attack's first samples make several.
    private let spacing = 0.006
    private var last: Candidate?

    /// - Parameters:
    ///   - sampleRate: in Hz.
    ///   - gate: the noise gate in dBFS; quieter sound never makes a candidate.
    init(sampleRate: Double, gate: Double) {
        let gate = Float(pow(10, gate / 20))
        // 1 and 3 dB in amplitude; 6 dB for the highs.
        level = RiseDetector(sampleRate: sampleRate, floor: gate, release: 0.05, weakRise: 1.122, strongRise: 1.413)
        highs = RiseDetector(sampleRate: sampleRate, floor: gate / 5, release: 0.015, weakRise: 2, strongRise: 2)
        highPass = Butterworth(.highPass, frequency: 3000, sampleRate: sampleRate)
    }

    /// Feeds one sample at stream time `time`; returns a candidate if one is at this sample.
    mutating func add(_ sample: Float, time: Double) -> Candidate? {
        let isBrighter = highs.add(highPass.process(sample)) != .none
        let rise = level.add(sample)
        guard rise != .none || isBrighter else { return nil }
        let candidate = Candidate(time: time, isStrong: rise == .strong, isBrighter: isBrighter)
        if let last, time - last.time < spacing, last.isStrong || !candidate.isStrong, last.isBrighter || !isBrighter { return nil }
        last = candidate
        return candidate
    }
}

/// Compares a peak envelope (instant attack) with its highest value over the last 25 ms. A decaying tail never rises.
private struct RiseDetector: Sendable {
    enum Rise: Sendable { case none, weak, strong }

    private let floor: Float
    private let release: Float
    private let weakRise: Float, strongRise: Float
    private let frameLength: Int
    private var envelope: Float = 0
    /// Envelope at the end of each recent frame.
    private var history: [Float]
    private var historyIndex = 0
    private var samplesInFrame = 0
    private var weakLevel: Float, strongLevel: Float
    private var isOverWeak = false, isOverStrong = false

    init(sampleRate: Double, floor: Float, release: Double, weakRise: Float, strongRise: Float) {
        self.floor = floor
        self.release = Float(exp(-1 / (release * sampleRate)))
        self.weakRise = weakRise
        self.strongRise = strongRise
        frameLength = max(1, Int(sampleRate / 750))           // about 1.3 ms
        history = [Float](repeating: 0, count: max(1, Int(0.025 * sampleRate) / frameLength))
        weakLevel = floor
        strongLevel = floor
    }

    /// The rise that begins at this sample; none while one goes on.
    mutating func add(_ sample: Float) -> Rise {
        envelope = max(abs(sample), envelope * release)
        var rise = Rise.none
        if envelope >= strongLevel, !isOverStrong {
            rise = .strong
            isOverStrong = true
            isOverWeak = true
        } else if envelope >= weakLevel, !isOverWeak {
            rise = .weak
            isOverWeak = true
        }
        samplesInFrame += 1
        if samplesInFrame == frameLength {
            samplesInFrame = 0
            history[historyIndex] = envelope
            historyIndex = (historyIndex + 1) % history.count
            let recentHigh = history.max() ?? 0
            strongLevel = recentHigh < floor ? floor : recentHigh * strongRise
            weakLevel = recentHigh < floor ? floor : recentHigh * weakRise
            if envelope < strongLevel { isOverStrong = false }
            if envelope < weakLevel { isOverWeak = false }
        }
        return rise
    }
}
