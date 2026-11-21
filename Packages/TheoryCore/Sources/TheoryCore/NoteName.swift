import Foundation

/// A letter name A–G, without accidental.
public enum Letter: Int, Hashable, Sendable, Codable, CaseIterable {
    case c, d, e, f, g, a, b

    /// The pitch class of the natural note (C = 0 … B = 11).
    public var naturalPitchClass: PitchClass {
        PitchClass([0, 2, 4, 5, 7, 9, 11][rawValue])
    }

    /// The letter `steps` letters above this one (wrapping B → C). Negative steps go down.
    public func advanced(by steps: Int) -> Letter {
        Letter(rawValue: ((rawValue + steps) % 7 + 7) % 7)!
    }

    public var symbol: String { ["C", "D", "E", "F", "G", "A", "B"][rawValue] }
}

/// A spelled note: a letter plus an accidental (in semitones: −2 = 𝄫, −1 = ♭, 0 = ♮, 1 = ♯, 2 = 𝄪).
///
/// The written name of a pitch class (see "Spelling" in GLOSSARY.md). Two note names can share a
/// pitch class (A♯ and B♭); which one is right depends on the key or scale.
public struct NoteName: Hashable, Sendable, Codable {
    public let letter: Letter
    public let accidental: Int

    public init(_ letter: Letter, _ accidental: Int = 0) {
        self.letter = letter
        self.accidental = accidental
    }

    public var pitchClass: PitchClass { letter.naturalPitchClass + Interval(accidental) }

    /// The spelling with sharps, used when no key applies.
    public init(sharpSpelling pitchClass: PitchClass) {
        let table: [(Letter, Int)] = [(.c, 0), (.c, 1), (.d, 0), (.d, 1), (.e, 0), (.f, 0),
                                      (.f, 1), (.g, 0), (.g, 1), (.a, 0), (.a, 1), (.b, 0)]
        let (letter, accidental) = table[pitchClass.value]
        self.init(letter, accidental)
    }

    /// The spelling with flats, used for out-of-key notes in flat keys.
    public init(flatSpelling pitchClass: PitchClass) {
        let table: [(Letter, Int)] = [(.c, 0), (.d, -1), (.d, 0), (.e, -1), (.e, 0), (.f, 0),
                                      (.g, -1), (.g, 0), (.a, -1), (.a, 0), (.b, -1), (.b, 0)]
        let (letter, accidental) = table[pitchClass.value]
        self.init(letter, accidental)
    }

    /// The note name on `letter` that sounds `pitchClass` (accidental chosen to fit, −6…+5).
    public init(_ letter: Letter, spelling pitchClass: PitchClass) {
        var accidental = letter.naturalPitchClass.interval(upTo: pitchClass).semitones
        if accidental > 6 { accidental -= 12 }
        self.init(letter, accidental)
    }

    // Common names, for readable call sites and tests.
    public static let c = NoteName(.c), d = NoteName(.d), e = NoteName(.e), f = NoteName(.f)
    public static let g = NoteName(.g), a = NoteName(.a), b = NoteName(.b)
    public static let cSharp = NoteName(.c, 1), dSharp = NoteName(.d, 1), fSharp = NoteName(.f, 1)
    public static let gSharp = NoteName(.g, 1), aSharp = NoteName(.a, 1)
    public static let cFlat = NoteName(.c, -1), dFlat = NoteName(.d, -1), eFlat = NoteName(.e, -1)
    public static let gFlat = NoteName(.g, -1), aFlat = NoteName(.a, -1), bFlat = NoteName(.b, -1)
}

extension NoteName: CustomStringConvertible {
    /// For example "C", "B♭", "F♯", "E𝄪".
    public var description: String {
        let mark: String = switch accidental {
        case 0: ""
        case 1: "♯"
        case 2: "𝄪"
        case -1: "♭"
        case -2: "𝄫"
        case let n where n > 0: String(repeating: "♯", count: n)
        default: String(repeating: "♭", count: -accidental)
        }
        return letter.symbol + mark
    }
}
