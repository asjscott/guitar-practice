import Foundation

/// The metronome's click: a struck wooden block, made rather than sampled. It is quiet within 40 ms, so that it
/// can't hold a pitch for `PlayedNote.stability`. Used by the app's metronome and by the listener's tests.
public enum Click {
    /// A wooden block's modes are not harmonic: each has a frequency as a multiple of the lowest, a share of the
    /// sound, and how fast it dies away, in seconds. The higher ones die first: a bright strike, then a duller body.
    private static let modes: [(ratio: Double, amount: Double, decay: Double)] = [
        (1, 1, 0.0052),
        (1.47, 0.6, 0.0042),
        (2.09, 0.45, 0.0028),
        (2.83, 0.25, 0.0018),
    ]
    private static let duration = 0.04

    /// The samples of one click, −1…1. An emphasised click is higher and louder.
    public static func samples(emphasised: Bool, sampleRate: Double) -> [Float] {
        let lowest = emphasised ? 1760.0 : 1320.0
        let peak: Float = emphasised ? 0.9 : 0.5
        let count = Int(duration * sampleRate)
        let fadeOut = 0.005 * sampleRate
        let raw = (0..<count).map { index -> Float in
            let time = Double(index) / sampleRate
            let body = modes.reduce(0.0) { sum, mode in
                sum + mode.amount * exp(-time / mode.decay) * sin(2 * .pi * lowest * mode.ratio * time)
            }
            // Half a millisecond to full strength, so that it knocks rather than ticks.
            return Float(body * min(1, time / 0.0005) * min(1, Double(count - index) / fadeOut))
        }
        let loudest = raw.reduce(0) { max($0, abs($1)) }
        return loudest > 0 ? raw.map { $0 * peak / loudest } : raw
    }
}
