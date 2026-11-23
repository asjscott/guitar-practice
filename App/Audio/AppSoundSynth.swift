import Foundation
import PracticeCore
import TheoryCore

/// Makes the app's sounds as mono samples: a plucked string (Karplus–Strong) and a two-note chime.
enum AppSoundSynth {
    static func samples(of sound: AppSound, sampleRate: Double) -> [Float] {
        switch sound {
        case .tones(let tones):
            tones.flatMap { pluck($0.pitch, frames: frames(in: $0.duration, at: sampleRate), sampleRate: sampleRate) }
        case .chime:
            chime(level: 0.3, frames: frames(in: sound.duration, at: sampleRate), sampleRate: sampleRate)
        case .softChime:
            chime(level: 0.12, frames: frames(in: sound.duration, at: sampleRate), sampleRate: sampleRate)
        }
    }

    private static func frames(in duration: Duration, at sampleRate: Double) -> Int {
        Int((duration / .seconds(1) * sampleRate).rounded())
    }

    private static func frequency(of pitch: Pitch) -> Double {
        440 * pow(2, Double(pitch.midi - 69) / 12)
    }

    /// Karplus–Strong: a burst of noise round a delay line one period long, averaged on each pass. The average
    /// delays by half a sample and an all-pass filter by the rest of the period's fraction, so it is in tune.
    private static func pluck(_ pitch: Pitch, frames: Int, sampleRate: Double) -> [Float] {
        let period = sampleRate / frequency(of: pitch)
        // Keeps the all-pass delay within 0.3–1.3 samples, where it is well behaved.
        let length = max(2, Int(period - 0.5 - 0.3))
        let fraction = period - 0.5 - Double(length)
        let allPass = Float((1 - fraction) / (1 + fraction))
        let loss: Float = 0.998

        var line = noiseBurst(length)
        var output = [Float](repeating: 0, count: frames)
        var index = 0
        var lastLine: Float = 0, lastAverage: Float = 0, lastAllPass: Float = 0
        for frame in 0..<frames {
            let sample = line[index]
            output[frame] = sample
            let average = loss * 0.5 * (sample + lastLine)
            lastLine = sample
            let delayed = allPass * (average - lastAllPass) + lastAverage
            lastAverage = average
            lastAllPass = delayed
            line[index] = delayed
            index = index + 1 == length ? 0 : index + 1
        }
        return shaped(output, peak: 0.5, sampleRate: sampleRate)
    }

    /// Noise with its highs softened and no offset; the same every time, so that tones sound alike.
    private static func noiseBurst(_ length: Int) -> [Float] {
        var state: UInt32 = 0x2545_F491
        var smoothed: Float = 0
        var burst = (0..<length).map { _ -> Float in
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            smoothed += 0.6 * (Float(state) / Float(UInt32.max) * 2 - 1 - smoothed)
            return smoothed
        }
        let mean = burst.reduce(0, +) / Float(length)
        for index in burst.indices { burst[index] -= mean }
        return burst
    }

    /// E6 then A6, each a sine with a touch of its octave, dying away.
    private static func chime(level: Double, frames: Int, sampleRate: Double) -> [Float] {
        let notes = [(pitch: Pitch(88), start: 0.0), (pitch: Pitch(93), start: 0.18)]
        let samples = (0..<frames).map { frame -> Float in
            let time = Double(frame) / sampleRate
            let sum = notes.filter { time >= $0.start }.reduce(0.0) { sum, note in
                let age = time - note.start
                let angle = 2 * Double.pi * frequency(of: note.pitch) * age
                return sum + (sin(angle) + 0.25 * sin(2 * angle)) * exp(-age * 6) * min(1, age / 0.005)
            }
            return Float(sum)
        }
        return shaped(samples, peak: Float(level), sampleRate: sampleRate)
    }

    /// Scaled to a peak, with a 1 ms fade in and a 30 ms fade out so that it starts and ends without a click.
    private static func shaped(_ samples: [Float], peak: Float, sampleRate: Double) -> [Float] {
        let loudest = samples.reduce(0) { max($0, abs($1)) }
        guard loudest > 0 else { return samples }
        let fadeIn = Float(sampleRate * 0.001), fadeOut = Float(sampleRate * 0.03)
        return samples.enumerated().map { index, sample in
            sample * peak / loudest * min(1, Float(index) / fadeIn) * min(1, Float(samples.count - index) / fadeOut)
        }
    }
}
