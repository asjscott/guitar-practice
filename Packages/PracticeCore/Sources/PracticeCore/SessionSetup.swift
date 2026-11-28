import TheoryCore

/// The frets a session uses, counted from the capo. The raw values are saved as preferences: never change them.
public enum SessionRange: String, CaseIterable, Hashable, Sendable {
    case first12, wholeNeck

    public var title: String {
        switch self {
        case .first12: "First 12 frets"
        case .wholeNeck: "Whole neck"
        }
    }

    public func frets(on fretboard: Fretboard) -> ClosedRange<Int> {
        switch self {
        case .first12: fretboard.playableFrets(upTo: 12)
        case .wholeNeck: fretboard.playableFrets
        }
    }
}

/// What the player chooses before a session: the note drills' notes and frets. There is no time budget.
public struct SessionSetup: Hashable, Sendable {
    public let notes: DrillOptions.Notes
    public let range: SessionRange

    public init(notes: DrillOptions.Notes = .naturals, range: SessionRange = .first12) {
        self.notes = notes
        self.range = range
    }

    public func drillOptions(on fretboard: Fretboard) -> DrillOptions {
        var options = DrillOptions()
        options.notes = notes
        options.frets = range.frets(on: fretboard)
        return options
    }
}
