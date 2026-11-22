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

    /// Whether the preset's open strings are spelled with flats (E♭ standard: E♭ A♭ D♭ …),
    /// matching its name. Other presets, and custom tunings, use sharps.
    public var spellsWithFlats: Bool {
        switch self {
        case .eFlatStandard: true
        case .standard, .dropD, .dadgad, .openG, .openD: false
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

    /// The open strings' names with octave, string 6 first, with no key as context (for
    /// Settings): flats when the tuning is a flat-named preset ("E♭2"), else sharps ("D♯2").
    public var openPitchNames: [String] {
        strings.map { string in
            // Flat and sharp spellings never cross B–C, so the pitch's octave number holds.
            "\(openNoteName(ofString: string))\(openPitch(ofString: string).octave)"
        }
    }

    /// A string's open note name without octave, spelled as in `openPitchNames`: flats for a
    /// flat-named preset, else sharps. Ignores any capo.
    public func openNoteName(ofString string: Int) -> NoteName {
        let pitchClass = openPitch(ofString: string).pitchClass
        let flats = preset?.spellsWithFlats ?? false
        return flats ? NoteName(flatSpelling: pitchClass) : NoteName(sharpSpelling: pitchClass)
    }

    /// A string named by its guitarist number and open note, as drills show it: "string 3 (G)".
    /// Names exactly one string even when open notes repeat (DADGAD). Ignores any capo.
    public func stringLabel(ofString string: Int) -> String {
        "string \(stringNumber(ofString: string)) (\(openNoteName(ofString: string)))"
    }
}
