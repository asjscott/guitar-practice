import Foundation

/// A second-order filter section, run one sample at a time.
struct Biquad: Sendable {
    enum Kind: Sendable { case lowPass, highPass }

    private let b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    private var s1: Float = 0, s2: Float = 0

    /// - Parameter q: 0.5412 and 1.3066 in turn make a fourth-order Butterworth filter.
    init(_ kind: Kind, frequency: Double, q: Double, sampleRate: Double) {
        let angle = 2 * Double.pi * min(frequency / sampleRate, 0.45)
        let alpha = sin(angle) / (2 * q), cosine = cos(angle), a0 = 1 + alpha
        let edge = kind == .lowPass ? (1 - cosine) / 2 : (1 + cosine) / 2
        b0 = Float(edge / a0)
        b1 = Float((kind == .lowPass ? 1 - cosine : -(1 + cosine)) / a0)
        b2 = b0
        a1 = Float(-2 * cosine / a0)
        a2 = Float((1 - alpha) / a0)
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + s1
        s1 = b1 * x - a1 * y + s2
        s2 = b2 * x - a2 * y
        return y
    }
}

/// A fourth-order Butterworth filter.
struct Butterworth: Sendable {
    private var first: Biquad, second: Biquad

    init(_ kind: Biquad.Kind, frequency: Double, sampleRate: Double) {
        first = Biquad(kind, frequency: frequency, q: 0.5412, sampleRate: sampleRate)
        second = Biquad(kind, frequency: frequency, q: 1.3066, sampleRate: sampleRate)
    }

    mutating func process(_ x: Float) -> Float { second.process(first.process(x)) }
}
