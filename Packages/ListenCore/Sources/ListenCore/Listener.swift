import Foundation

/// The listener: ListenCore's public face. Feed it blocks of mono samples,
/// in stream order, and it reports what it hears.
///
/// Fixed for Phase 1: A4 = 440 Hz, equal temperament, a noise gate at
/// about −50 dBFS. The pitch detector and smoothing are internal.
/// Tuner smoothing never affects played notes: they come from the raw estimates.
public struct Listener: Sendable {
    /// Signal below this RMS level (dBFS) counts as no signal.
    public static let noiseGate = -50.0

    private var sampleRate = 0.0
    private var detector = PitchDetector(sampleRate: 48_000)
    private var windowSize = 0
    private var hopSize = 0
    /// Recent samples; the last `windowSize` of them are analysed.
    private var window: [Float] = []
    private var samplesSinceAnalysis = 0
    private var smoother = PitchSmoother()
    private var tunerReading: TunerReading?
    private var onsets = OnsetDetector(sampleRate: 48_000, gate: Listener.noiseGate)
    private var notes = NoteTracker(windowDuration: 0)
    private var playedNotes: [PlayedNote] = []

    /// A listener with nothing heard yet.
    public init() {}

    /// Feeds the next block of samples.
    ///
    /// - Parameters:
    ///   - samples: mono samples in −1…1, any block size.
    ///   - sampleRate: in Hz; a change resets the listener.
    ///   - time: stream time of the block's first sample, in seconds.
    /// - Returns: what the listener reports after this block.
    public mutating func process(_ samples: some Collection<Float>, sampleRate: Double, time: Double) -> ListenerOutput {
        if sampleRate != self.sampleRate { reset(sampleRate: sampleRate) }
        playedNotes.removeAll()
        for (index, sample) in samples.enumerated() {
            let sampleTime = time + Double(index) / sampleRate
            if onsets.add(sample, time: sampleTime) { notes.onsetDetected(at: sampleTime) }
            window.append(sample)
            samplesSinceAnalysis += 1
            if window.count >= windowSize, samplesSinceAnalysis >= hopSize {
                samplesSinceAnalysis = 0
                if window.count > 4 * windowSize { window.removeFirst(window.count - windowSize) }
                let end = sampleTime + 1 / sampleRate
                analyse(Array(window.suffix(windowSize)), start: end - Double(windowSize) / sampleRate, end: end)
            }
        }
        return ListenerOutput(tunerReading: tunerReading, playedNotes: playedNotes)
    }

    private mutating func reset(sampleRate: Double) {
        self.sampleRate = sampleRate
        detector = PitchDetector(sampleRate: sampleRate)
        // About 43 ms: three periods of Drop D's low D (73 Hz).
        windowSize = max(1024, Int(sampleRate * 2048 / 48_000))
        hopSize = windowSize / 4
        window.removeAll(keepingCapacity: true)
        window.reserveCapacity(4 * windowSize + 1)
        samplesSinceAnalysis = 0
        smoother = PitchSmoother()
        tunerReading = nil
        onsets = OnsetDetector(sampleRate: sampleRate, gate: Self.noiseGate)
        notes = NoteTracker(windowDuration: Double(windowSize) / sampleRate)
    }

    /// Analyses one window, from `start` to `end` in stream seconds.
    private mutating func analyse(_ samples: [Float], start: Double, end: Double) {
        guard Self.level(of: samples) >= Self.noiseGate else {
            notes.silence()
            smoother = PitchSmoother()
            tunerReading = nil
            return
        }
        guard let estimate = detector.estimate(samples) else {
            notes.noPitch()
            smoother = PitchSmoother()
            tunerReading = nil
            return
        }
        if let note = notes.estimate(frequency: estimate.frequency, start: start, end: end) {
            playedNotes.append(note)
        }
        tunerReading = TunerReading(frequency: smoother.add(estimate.frequency))
    }

    /// RMS level in dBFS.
    private static func level(of samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -.infinity }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return 10 * log10(sum / Double(samples.count))
    }
}

/// What the listener reports after a block of samples.
public struct ListenerOutput: Sendable, Equatable {
    /// The current tuner reading; nil when there is no signal.
    public let tunerReading: TunerReading?
    /// Played notes completed during this block, oldest first; usually none.
    public let playedNotes: [PlayedNote]
}
