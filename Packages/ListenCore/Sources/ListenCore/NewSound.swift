import Accelerate
import Foundation

/// The last half second of sound, to find the pitch of what began at a time while other notes ring on: the spectrum
/// after it less the spectrum before, and the pitch whose harmonics that leaves strongest (ADR 0005).
struct NewSound: Sendable {
    /// A pitch heard in what is new.
    struct Pitch: Sendable, Equatable {
        let midiNote: Int
        let frequency: Double
        /// How much of the sound after the time is new, by energy, 0–1.
        let share: Double
    }

    private let sampleRate: Double
    private var samples: [Float] = []
    private var end = 0.0
    private let capacity: Int
    /// Each spectrum's length: long enough to tell semitones apart on the low strings.
    private let length: Int
    /// The spectrum after starts this long after the time, once most of the pick's noise has gone.
    private let delay = 0.03
    private let fftLength = 8192
    /// MIDI notes looked for, as the pitch detector's 60–1500 Hz.
    private let notes = 35...90

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        capacity = Int(0.6 * sampleRate)
        length = Int(0.07 * sampleRate)
        samples.reserveCapacity(2 * capacity)
    }

    /// How long after a time its new sound can be weighed, in seconds.
    var wait: Double { delay + Double(length) / sampleRate }

    mutating func add(_ sample: Float, time: Double) {
        if samples.count == 2 * capacity { samples.removeFirst(capacity) }
        samples.append(sample)
        end = time + 1 / sampleRate
    }

    /// The pitch of what began at `time`, or nil if the sound around it isn't kept or nothing in it has a pitch.
    func pitch(at time: Double) -> Pitch? {
        let begin = end - Double(samples.count) / sampleRate
        let before = Int(((time - 0.005 - begin) * sampleRate).rounded()) - length
        let after = min(Int(((time + delay - begin) * sampleRate).rounded()), samples.count - length)
        guard before >= 0, after > before + length / 2, fftLength >= length else { return nil }
        guard let ringing = spectrum(from: before), let now = spectrum(from: after) else { return nil }
        let new = zip(now, ringing).map { max(0, $0 - $1) }
        let nowEnergy = now.reduce(0) { $0 + Double($1 * $1) }
        guard nowEnergy > 0 else { return nil }
        let share = new.reduce(0) { $0 + Double($1 * $1) } / nowEnergy
        let binWidth = sampleRate / Double(fftLength)
        guard let best = notes.map({ (note: $0, score: score(new, $0, binWidth)) }).max(by: { $0.score < $1.score }),
              best.score > 0 else { return nil }
        return Pitch(midiNote: best.note, frequency: frequency(now, best.note, binWidth), share: share)
    }

    /// Harmonic summation, each harmonic weighted so that a pitch an octave below doesn't win on the same partials
    /// (A. Klapuri, "Multiple fundamental frequency estimation by summing harmonic amplitudes", 2006).
    private func score(_ spectrum: [Float], _ midiNote: Int, _ binWidth: Double) -> Double {
        let fundamental = 440 * pow(2, Double(midiNote - 69) / 12)
        var sum = 0.0
        for harmonic in 1...20 {
            let frequency = Double(harmonic) * fundamental
            guard frequency < 5000 else { break }
            sum += Double(peak(spectrum, near: frequency, binWidth).height) * (fundamental + 27) / (frequency + 320)
        }
        return sum
    }

    /// The fundamental, from where the strongest harmonics peak in the sound after; less is lost there than in what is new.
    private func frequency(_ spectrum: [Float], _ midiNote: Int, _ binWidth: Double) -> Double {
        let fundamental = 440 * pow(2, Double(midiNote - 69) / 12)
        var weighted = 0.0, weights = 0.0
        for harmonic in 1...8 {
            let peak = peak(spectrum, near: Double(harmonic) * fundamental, binWidth)
            guard peak.height > 0 else { continue }
            weighted += Double(peak.height) * peak.frequency / Double(harmonic)
            weights += Double(peak.height)
        }
        return weights > 0 ? weighted / weights : fundamental
    }

    /// The highest bin within a quarter of a semitone of a frequency, its frequency refined between its neighbours.
    private func peak(_ spectrum: [Float], near frequency: Double, _ binWidth: Double) -> (height: Float, frequency: Double) {
        let low = max(1, Int(frequency * 0.985 / binWidth)), high = Int(frequency * 1.015 / binWidth) + 1
        guard high < spectrum.count - 1, low <= high else { return (0, frequency) }
        var best = low
        for bin in low...high where spectrum[bin] > spectrum[best] { best = bin }
        let a = spectrum[best - 1], b = spectrum[best], c = spectrum[best + 1]
        let denominator = a - 2 * b + c
        let shift = denominator == 0 ? 0 : Double(0.5 * (a - c) / denominator)
        return (b, (Double(best) + max(-0.5, min(0.5, shift))) * binWidth)
    }

    /// The magnitude spectrum of `length` samples from an index, tapered (Hann) and padded.
    private func spectrum(from first: Int) -> [Float]? {
        let log2n = vDSP_Length(log2(Double(fftLength)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }
        var padded = [Float](repeating: 0, count: fftLength)
        for index in 0..<length {
            let weight = 0.5 - 0.5 * cos(2 * Float.pi * (Float(index) + 0.5) / Float(length))
            padded[index] = samples[first + index] * weight
        }
        var real = [Float](repeating: 0, count: fftLength / 2), imaginary = real, magnitudes = real
        real.withUnsafeMutableBufferPointer { real in
            imaginary.withUnsafeMutableBufferPointer { imaginary in
                var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginary.baseAddress!)
                padded.withUnsafeBufferPointer { padded in
                    padded.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftLength / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(fftLength / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(fftLength / 2))
            }
        }
        return magnitudes
    }
}
