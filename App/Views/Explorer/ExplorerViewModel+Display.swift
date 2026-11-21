import TheoryCore

/// Display options applied to the explorer's diagram: label mode and the debug heatmap.
extension ExplorerViewModel {
    /// The heatmap values, or nil when the overlay is off. Only playable locations get a value,
    /// so the tint follows the fretboard (a capo narrows it).
    var heat: [FretboardLocation: Double]? {
        guard showsDebugHeatmap else { return nil }
        return DebugHeatFill(seed: debugHeatSeed).values(for: fretboard.allLocations)
    }

    func shuffleDebugHeat() {
        debugHeatSeed = UInt64.random(in: .min ... .max)
    }
}

/// Random but stable heatmap values for debugging the tint: each location's value depends
/// only on the seed and the location, so the fill doesn't flicker when the view redraws or
/// when the playable range changes.
struct DebugHeatFill {
    var seed: UInt64

    func values(for locations: [FretboardLocation]) -> [FretboardLocation: Double] {
        Dictionary(uniqueKeysWithValues: locations.map { ($0, value(at: $0)) })
    }

    /// A value from 0 to 1 (SplitMix64 hash of the seed and the location).
    func value(at location: FretboardLocation) -> Double {
        var z = seed &+ UInt64(truncatingIfNeeded: location.string &* 1_000 &+ location.fret) &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
