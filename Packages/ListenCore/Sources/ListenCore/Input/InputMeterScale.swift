import Foundation

/// Maps input level to the input meter: −60 dBFS (and quieter) is empty, 0 dBFS is full, linear in dB between.
public enum InputMeterScale {
    public static let floorDBFS = -60.0

    /// 0–1 meter fraction for a level in dBFS.
    public static func fraction(dBFS: Double) -> Double {
        min(max((dBFS - floorDBFS) / -floorDBFS, 0), 1)
    }

    /// The block's peak in dBFS; silence or an empty block gives −∞.
    public static func peakDBFS(_ samples: UnsafeBufferPointer<Float>) -> Double {
        var peak: Float = 0
        for sample in samples { peak = max(peak, abs(sample)) }
        return 20 * log10(Double(peak))
    }
}
