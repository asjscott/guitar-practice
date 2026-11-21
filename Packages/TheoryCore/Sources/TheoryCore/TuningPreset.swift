import Foundation

/// The named six-string tunings offered in Settings, in picker order.
public enum TuningPreset: String, CaseIterable, Hashable, Sendable, Codable {
    case standard
    case dropD
    case dadgad
    case openG
    case openD
    case eFlatStandard

    /// The name shown in the tuning picker.
    public var name: String {
        switch self {
        case .standard: "Standard"
        case .dropD: "Drop D"
        case .dadgad: "DADGAD"
        case .openG: "Open G"
        case .openD: "Open D"
        case .eFlatStandard: "E♭ standard"
        }
    }

    /// The preset's open pitches, string 6 first.
    public var tuning: Tuning {
        let midi: [Int] = switch self {
        case .standard: [40, 45, 50, 55, 59, 64]      // E2 A2 D3 G3 B3 E4
        case .dropD: [38, 45, 50, 55, 59, 64]         // D2 A2 D3 G3 B3 E4
        case .dadgad: [38, 45, 50, 55, 57, 62]        // D2 A2 D3 G3 A3 D4
        case .openG: [38, 43, 50, 55, 59, 62]         // D2 G2 D3 G3 B3 D4
        case .openD: [38, 45, 50, 54, 57, 62]         // D2 A2 D3 F♯3 A3 D4
        case .eFlatStandard: [39, 44, 49, 54, 58, 63] // E♭2 A♭2 D♭3 G♭3 B♭3 E♭4
        }
        return Tuning(midi.map(Pitch.init))
    }
}

extension Tuning {
    /// The preset with exactly these open pitches, or nil for a custom tuning.
    public var preset: TuningPreset? {
        TuningPreset.allCases.first { $0.tuning == self }
    }
}
