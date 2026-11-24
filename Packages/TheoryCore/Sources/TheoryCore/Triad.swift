import Foundation

/// A three-note chord on a spelled root: root, 3rd and 5th.
///
/// Chord tones are spelled by letter from the root (root, root + 2 letters, root + 4 letters),
/// so B♭ major is B♭ D F and D♯ minor is D♯ F♯ A♯.
public struct Triad: Hashable, Sendable, Codable {
    /// Major and minor for now; diminished and augmented come later.
    public enum Quality: String, Hashable, Sendable, Codable, CaseIterable {
        case major, minor

        /// Semitones above the root of the 3rd and the 5th.
        var thirdAndFifth: (Interval, Interval) {
            switch self {
            case .major: (Interval(4), Interval(7))
            case .minor: (Interval(3), Interval(7))
            }
        }
    }

    /// Which chord tone is lowest (see "Inversion" in GLOSSARY.md).
    public enum Inversion: String, Hashable, Sendable, Codable, CaseIterable {
        case root, first, second

        /// For example "Root position", "1st inversion".
        public var name: String {
            switch self {
            case .root: "Root position"
            case .first: "1st inversion"
            case .second: "2nd inversion"
            }
        }
    }

    public let quality: Quality
    public let root: NoteName

    public init(_ quality: Quality, root: NoteName) {
        self.quality = quality
        self.root = root
    }

    /// Root, 3rd, 5th, spelled.
    public var notes: [NoteName] {
        let (third, fifth) = quality.thirdAndFifth
        return [root,
                NoteName(root.letter.advanced(by: 2), spelling: root.pitchClass + third),
                NoteName(root.letter.advanced(by: 4), spelling: root.pitchClass + fifth)]
    }

    public var pitchClasses: [PitchClass] { notes.map(\.pitchClass) }

    /// The chord tones from lowest to highest in close position for an inversion:
    /// root position R 3 5, 1st inversion 3 5 R, 2nd inversion 5 R 3.
    public func tones(in inversion: Inversion) -> [NoteName] {
        let notes = notes
        return switch inversion {
        case .root: notes
        case .first: [notes[1], notes[2], notes[0]]
        case .second: [notes[2], notes[0], notes[1]]
        }
    }

    /// For example "C major", "B♭ minor".
    public var name: String { "\(root) \(quality.rawValue)" }
}

extension Triad: CustomStringConvertible {
    public var description: String { name }
}

extension Key {
    /// The key's tonic triad: major in a major key, minor in a minor key.
    public var triad: Triad { Triad(mode == .major ? .major : .minor, root: tonic) }

    /// The key's major and minor triads, in its spelling, by degree from the tonic. The diminished one is left out.
    public var chords: [Triad] {
        let notes = notes
        return notes.indices.compactMap { degree in
            let tones = [0, 2, 4].map { notes[(degree + $0) % notes.count] }
            return Triad.Quality.allCases.map { Triad($0, root: tones[0]) }.first { $0.notes == tones }
        }
    }
}
