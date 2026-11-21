import Foundation

/// A scale on a spelled tonic, defined by a degree formula (for example blues = 1 ♭3 4 ♭5 5 ♭7).
///
/// Scale notes are spelled from the formula relative to the tonic, so A blues has E♭ (♭5), not D♯.
public struct Scale: Hashable, Sendable, Codable {
    /// The five scales the app knows.
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        case major, naturalMinor, majorPentatonic, minorPentatonic, blues

        /// The degree formula: (degree 1–7, alteration in semitones from the major scale degree).
        public var degrees: [Degree] {
            switch self {
            case .major: [.init(1), .init(2), .init(3), .init(4), .init(5), .init(6), .init(7)]
            case .naturalMinor: [.init(1), .init(2), .init(3, -1), .init(4), .init(5), .init(6, -1), .init(7, -1)]
            case .majorPentatonic: [.init(1), .init(2), .init(3), .init(5), .init(6)]
            case .minorPentatonic: [.init(1), .init(3, -1), .init(4), .init(5), .init(7, -1)]
            case .blues: [.init(1), .init(3, -1), .init(4), .init(5, -1), .init(5), .init(7, -1)]
            }
        }

        /// Whether the scale is a minor-side scale (natural minor, minor pentatonic, blues).
        public var isMinor: Bool {
            switch self {
            case .major, .majorPentatonic: false
            case .naturalMinor, .minorPentatonic, .blues: true
            }
        }

        /// The key mode the scale is built in: minor for minor-side scales, else major.
        public var mode: Key.Mode { isMinor ? .minor : .major }

        /// Seven-note scales (major, natural minor): the only ones with 3NPS patterns.
        public var isSevenNote: Bool { degrees.count == 7 }

        /// For example "major", "natural minor", "minor pentatonic", "blues".
        public var name: String {
            switch self {
            case .major: "major"
            case .naturalMinor: "natural minor"
            case .majorPentatonic: "major pentatonic"
            case .minorPentatonic: "minor pentatonic"
            case .blues: "blues"
            }
        }
    }

    /// One scale degree: a number 1–7 and an alteration from the major scale (−1 = ♭, +1 = ♯).
    public struct Degree: Hashable, Sendable, Codable {
        public let number: Int
        public let alteration: Int

        public init(_ number: Int, _ alteration: Int = 0) {
            precondition((1...7).contains(number), "Scale degrees are 1–7")
            self.number = number
            self.alteration = alteration
        }

        /// Semitones above the tonic.
        public var interval: Interval {
            Interval([0, 2, 4, 5, 7, 9, 11][number - 1] + alteration)
        }

        /// For example "1", "♭3", "♭5".
        public var name: String {
            String(repeating: alteration < 0 ? "♭" : "♯", count: abs(alteration)) + "\(number)"
        }
    }

    public let kind: Kind
    public let tonic: NoteName

    public init(_ kind: Kind, tonic: NoteName) {
        self.kind = kind
        self.tonic = tonic
    }

    /// The scale of `kind` on the key's own tonic: A minor + natural minor is A natural minor,
    /// A minor + blues is A blues. A key in the other mode first moves to that mode on the same
    /// tonic pitch class (`Key.withMode`), so D♭ major + natural minor is C♯ natural minor.
    public init(_ kind: Kind, in key: Key) {
        self.init(kind, tonic: key.withMode(kind.mode).tonic)
    }

    /// The key this scale belongs to (tonic and mode), which spells notes outside the scale.
    /// A minor key takes its relative major's signature.
    public var key: Key { Key(tonic: tonic, mode: kind.mode) }

    /// The scale notes from the tonic, spelled by the degree formula.
    public var notes: [NoteName] {
        kind.degrees.map { degree in
            NoteName(tonic.letter.advanced(by: degree.number - 1),
                     spelling: tonic.pitchClass + degree.interval)
        }
    }

    public var pitchClasses: [PitchClass] { notes.map(\.pitchClass) }

    public func contains(_ pitchClass: PitchClass) -> Bool { pitchClasses.contains(pitchClass) }

    /// The scale degree a pitch class plays in this scale, or nil when it is not a scale note.
    public func degree(of pitchClass: PitchClass) -> Degree? {
        zip(kind.degrees, pitchClasses).first { $0.1 == pitchClass }?.0
    }

    /// The spelling of a pitch class with this scale as context: scale notes follow the degree
    /// formula; other notes follow the scale's key.
    public func spell(_ pitchClass: PitchClass) -> NoteName {
        notes.first { $0.pitchClass == pitchClass } ?? key.spell(pitchClass)
    }

    /// For example "C major", "A natural minor", "A blues".
    public var name: String { "\(tonic) \(kind.name)" }
}

extension Scale: CustomStringConvertible {
    public var description: String { name }
}
