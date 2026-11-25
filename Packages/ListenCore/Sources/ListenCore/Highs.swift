import Foundation

/// How strong the sound above 1.5 kHz has been over the last half second, which a pick makes jump.
struct Highs: Sendable {
    private var filter: Butterworth
    private let frameLength: Int
    private let frameDuration: Double
    /// The peak in each recent frame of about 4 ms.
    private var peaks: [Float] = []
    private var peak: Float = 0
    private var samplesInFrame = 0
    private var end = 0.0

    init(sampleRate: Double) {
        filter = Butterworth(.highPass, frequency: 1500, sampleRate: sampleRate)
        frameLength = max(1, Int(sampleRate * 0.004))
        frameDuration = Double(frameLength) / sampleRate
    }

    mutating func add(_ sample: Float, time: Double) {
        peak = max(peak, abs(filter.process(sample)))
        samplesInFrame += 1
        guard samplesInFrame == frameLength else { return }
        samplesInFrame = 0
        if peaks.count == 250 { peaks.removeFirst(125) }
        peaks.append(peak)
        peak = 0
        end = time
    }

    /// How far the highs rose at a time: the 25 ms after it against the 40 ms before, in dB.
    func jump(at time: Double) -> Double {
        let before = strongest(from: time - 0.044, to: time - 0.004), after = strongest(from: time - 0.004, to: time + 0.025)
        return 20 * log10(Double(max(after, 1e-5) / max(before, 1e-5)))
    }

    private func strongest(from start: Double, to stop: Double) -> Float {
        let first = peaks.count - Int(((end - start) / frameDuration).rounded()), last = peaks.count - Int(((end - stop) / frameDuration).rounded())
        return peaks[max(0, min(first, peaks.count))..<max(0, min(max(first, last), peaks.count))].max() ?? 0
    }
}
