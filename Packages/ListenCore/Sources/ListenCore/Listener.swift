import Foundation

/// The listener: ListenCore's public face. Feed it blocks of mono samples,
/// in stream order, and it reports what it hears.
///
/// Fixed for Phase 1: A4 = 440 Hz, equal temperament, a noise gate at
/// about −50 dBFS. The pitch detector and smoothing are internal.
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
        for sample in samples {
            window.append(sample)
            samplesSinceAnalysis += 1
            if window.count >= windowSize, samplesSinceAnalysis >= hopSize {
                samplesSinceAnalysis = 0
                if window.count > 4 * windowSize { window.removeFirst(window.count - windowSize) }
                analyse(Array(window.suffix(windowSize)))
            }
        }
        return ListenerOutput(tunerReading: tunerReading)
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
    }

    private mutating func analyse(_ samples: [Float]) {
        guard Self.level(of: samples) >= Self.noiseGate,
              let estimate = detector.estimate(samples) else {
            smoother = PitchSmoother()
            tunerReading = nil
            return
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
}
