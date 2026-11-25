import Accelerate
import Foundation

/// The last third of a second of sound below about 1 kHz: mostly the notes, without the click.
struct LowSound: Sendable {
    private let sampleRate: Double
    private var filter: Butterworth
    private var samples: [Float] = []
    private var end = 0.0
    private let capacity: Int

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        filter = Butterworth(.lowPass, frequency: 1000, sampleRate: sampleRate)
        capacity = Int(0.35 * sampleRate)
        samples.reserveCapacity(2 * capacity)
    }

    mutating func add(_ sample: Float, time: Double) {
        if samples.count == 2 * capacity { samples.removeFirst(capacity) }
        samples.append(filter.process(sample))
        end = time + 1 / sampleRate
    }

    /// How alike a stretch is to the sound near `time`, were one steady pitch sounding through both: their
    /// correlation a whole number of periods apart, and the stretch's amplitude against the other's.
    func match(_ stretch: ClosedRange<Double>, period: Double, near time: Double) -> (similarity: Double, gain: Double) {
        let begin = end - Double(samples.count) / sampleRate
        let first = Int(((stretch.lowerBound - begin) * sampleRate).rounded())
        let count = Int((stretch.upperBound - stretch.lowerBound) * sampleRate)
        let middle = (stretch.lowerBound + stretch.upperBound) / 2
        let shift = Int((((time - middle) / period).rounded(.down) * period * sampleRate).rounded())
        let play = max(1, Int(period * sampleRate / 12))      // the pitch sags a little as a note settles
        guard first >= 0, count > 0, first + count <= samples.count else { return (0, 0) }
        // vDSP keeps this fast in Debug builds too, so the app can listen live.
        return samples.withUnsafeBufferPointer { buffer in
            func product(_ a: Int, _ b: Int) -> Double {
                var sum: Float = 0
                vDSP_dotpr(buffer.baseAddress! + a, 1, buffer.baseAddress! + b, 1, &sum, vDSP_Length(count))
                return Double(sum)
            }
            let own = product(first, first)
            var best = (similarity: 0.0, gain: 0.0)
            for offset in stride(from: -play, through: play, by: max(1, play / 6)) {
                let other = first + shift + offset
                guard other >= 0, other + count <= samples.count else { continue }
                let others = product(other, other)
                guard own > 0, others > 0 else { continue }
                let similarity = product(first, other) / (own * others).squareRoot()
                if similarity > best.similarity { best = (similarity, (own / others).squareRoot()) }
            }
            return best
        }
    }
}
