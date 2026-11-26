import Foundation

/// A sequence of chords written as Roman numerals, each lasting a number of bars of 4/4 (see "Progression" in
/// GLOSSARY.md). Played in a key of its mode, the numerals become triads spelled in the key.
public struct Progression: Hashable, Sendable, Identifiable {
    /// A chord as a Roman numeral: a degree of the key's scale, and a quality written by case (vi is minor).
    public struct Numeral: Hashable, Sendable {
        /// 1–7.
        public let degree: Int
        public let quality: Triad.Quality

        public init(_ degree: Int, _ quality: Triad.Quality) {
            precondition((1...7).contains(degree))
            self.degree = degree
            self.quality = quality
        }

        /// "vi", "IV", "VII".
        public var text: String {
            let upper = ["I", "II", "III", "IV", "V", "VI", "VII"][degree - 1]
            return quality == .major ? upper : upper.lowercased()
        }

        /// The triad on this degree of a key, spelled in the key.
        public func triad(in key: Key) -> Triad { Triad(quality, root: key.notes[degree - 1]) }
    }

    /// One chord of the progression and how many bars it lasts.
    public struct Step: Hashable, Sendable {
        public let numeral: Numeral
        public let bars: Int

        public init(_ numeral: Numeral, bars: Int = 1) {
            precondition(bars > 0)
            self.numeral = numeral
            self.bars = bars
        }
    }

    /// "I–V–vi–IV", "12-bar blues". Saved in the attempt log and with themes: never change it.
    public let id: String
    /// The mode of the keys it is played in.
    public let mode: Key.Mode
    public let steps: [Step]

    init(id: String, mode: Key.Mode, steps: [Step]) {
        precondition(!steps.isEmpty)
        self.id = id
        self.mode = mode
        self.steps = steps
    }

    /// Its name as shown: the id.
    public var name: String { id }

    /// The chords in a key of its mode, spelled in the key, one per step.
    public func chords(in key: Key) -> [Triad] { steps.map { $0.numeral.triad(in: key) } }

    /// How many bars one time through lasts.
    public var bars: Int { steps.map(\.bars).reduce(0, +) }

    // MARK: - The library

    /// Every progression the app offers, major ones first.
    public static let library: [Progression] = {
        func major(_ degree: Int) -> Numeral { Numeral(degree, .major) }
        func minor(_ degree: Int) -> Numeral { Numeral(degree, .minor) }
        /// One bar each, named by its numerals.
        func plain(_ mode: Key.Mode, _ numerals: [Numeral]) -> Progression {
            Progression(id: numerals.map(\.text).joined(separator: "–"), mode: mode, steps: numerals.map { Step($0) })
        }
        let (i, iv, v) = (major(1), major(4), major(5))
        return [
            plain(.major, [i, iv, v]),
            plain(.major, [i, v, minor(6), iv]),
            Progression(id: "ii–V–I", mode: .major, steps: [Step(minor(2)), Step(v), Step(i, bars: 2)]),
            plain(.major, [i, minor(6), iv, v]),
            plain(.major, [minor(6), iv, i, v]),
            Progression(id: "12-bar blues", mode: .major,
                        steps: [i, i, i, i, iv, iv, i, i, v, iv, i, v].map { Step($0) }),
            plain(.minor, [minor(1), minor(4), minor(5)]),
            plain(.minor, [minor(1), major(6), major(3), major(7)]),
        ]
    }()

    /// The library's progressions of one mode, in order.
    public static func library(_ mode: Key.Mode) -> [Progression] { library.filter { $0.mode == mode } }

    /// The library's progression with this id; nil if there is none.
    public static func named(_ id: String) -> Progression? { library.first { $0.id == id } }
}
