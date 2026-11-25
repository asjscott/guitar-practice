/// How many beats a bar has, and the note that makes a beat. Every beat is a click, whatever the note.
public struct TimeSignature: Hashable, Sendable {
    public static let beatCounts = 1...12
    public static let units = [4, 8]

    /// Offered with one tap.
    public static let common: [TimeSignature] = [(2, 4), (3, 4), (4, 4), (5, 4), (6, 8), (7, 8), (9, 8), (12, 8)]
        .map { TimeSignature(uncheckedBeats: $0.0, unit: $0.1) }

    public static let all: [TimeSignature] = units.flatMap { unit in
        beatCounts.map { TimeSignature(uncheckedBeats: $0, unit: unit) }
    }

    public static let fourFour = TimeSignature(uncheckedBeats: 4, unit: 4)

    public let beats: Int
    public let unit: Int

    /// Nil unless 1–12 over 4 or 8.
    public init?(beats: Int, unit: Int) {
        guard Self.beatCounts.contains(beats), Self.units.contains(unit) else { return nil }
        self.init(uncheckedBeats: beats, unit: unit)
    }

    /// From its `name`.
    public init?(name: String) {
        guard let signature = Self.all.first(where: { $0.name == name }) else { return nil }
        self = signature
    }

    private init(uncheckedBeats beats: Int, unit: Int) {
        self.beats = beats
        self.unit = unit
    }

    /// "6/8".
    public var name: String { "\(beats)/\(unit)" }

    /// The beats emphasised unless the player chooses: beat 1, and each group's first in compound time (6/8, 9/8, 12/8).
    public var usualEmphasis: Set<Int> {
        let isCompound = unit == 8 && beats > 3 && beats.isMultiple(of: 3)
        return isCompound ? Set(stride(from: 1, through: beats, by: 3)) : [1]
    }

    /// Whole bars, at least four clicks.
    public var countInClicks: Int {
        let bars = (4 + beats - 1) / beats
        return bars * beats
    }
}

/// A time signature and its emphasised beats. Beats count from 1.
public struct Meter: Hashable, Sendable {
    public let signature: TimeSignature
    public let emphasis: Set<Int>

    /// The usual emphasis unless given; beats that the bar doesn't have are left out.
    public init(_ signature: TimeSignature, emphasis: Set<Int>? = nil) {
        self.signature = signature
        self.emphasis = (emphasis ?? signature.usualEmphasis).filter { (1...signature.beats).contains($0) }
    }
}

/// The chosen time signature, and the emphasis chosen in each.
public struct MeterMemory: Hashable, Sendable {
    public var signature: TimeSignature
    private var chosen: [TimeSignature: Set<Int>] = [:]

    public init() { signature = .fourFour }

    /// From what was stored; whatever can't be read falls back to the default.
    public init(signature: String, emphasis: String) {
        self.signature = TimeSignature(name: signature) ?? .fourFour
        for entry in emphasis.split(separator: ";") {
            let parts = entry.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let signature = TimeSignature(name: String(parts[0])) else { continue }
            let beats = parts[1].split(separator: ",").compactMap { Int($0) }
            chosen[signature] = Meter(signature, emphasis: Set(beats)).emphasis
        }
    }

    /// For storing: "4/4:1,3;6/8:" (none in 6/8).
    public var storedEmphasis: String {
        chosen.map { signature, beats in "\(signature.name):\(beats.sorted().map(String.init).joined(separator: ","))" }
            .sorted().joined(separator: ";")
    }

    public var meter: Meter { Meter(signature, emphasis: chosen[signature]) }

    public mutating func toggleEmphasis(ofBeat beat: Int) {
        chosen[signature] = Meter(signature, emphasis: meter.emphasis.symmetricDifference([beat])).emphasis
    }
}
