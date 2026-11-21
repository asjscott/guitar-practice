import TheoryCore

/// The 12 keys the explorer's key picker offers, in the spec's order.
///
/// Placeholder until TheoryCore has `Key` with key-aware spelling (ticket #5): replace this
/// with TheoryCore's 12 app keys and take names from its spelling, then delete this file.
struct ExplorerKeyChoice: Hashable, Identifiable {
    let name: String
    let tonic: PitchClass

    var id: String { name }

    static let c = ExplorerKeyChoice(name: "C", tonic: PitchClass(0))

    static let all: [ExplorerKeyChoice] = [
        c,
        .init(name: "G", tonic: PitchClass(7)),
        .init(name: "D", tonic: PitchClass(2)),
        .init(name: "A", tonic: PitchClass(9)),
        .init(name: "E", tonic: PitchClass(4)),
        .init(name: "B", tonic: PitchClass(11)),
        .init(name: "F♯", tonic: PitchClass(6)),
        .init(name: "F", tonic: PitchClass(5)),
        .init(name: "B♭", tonic: PitchClass(10)),
        .init(name: "E♭", tonic: PitchClass(3)),
        .init(name: "A♭", tonic: PitchClass(8)),
        .init(name: "D♭", tonic: PitchClass(1)),
    ]
}
