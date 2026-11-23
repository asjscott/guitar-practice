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

/// What the player chooses before a session.
public struct SessionSetup: Hashable, Sendable {
    public static let minutesRange = 10...60
    public static let minutesStep = 5

    /// 10–60, in steps of 5.
    public let minutes: Int
    public let notes: DrillOptions.Notes
    public let range: SessionRange

    /// Minutes are brought to the nearest that is offered.
    public init(minutes: Int = 15, notes: DrillOptions.Notes = .naturals, range: SessionRange = .first12) {
        let bounded = min(max(minutes, Self.minutesRange.lowerBound), Self.minutesRange.upperBound)
        self.minutes = (bounded + Self.minutesStep / 2) / Self.minutesStep * Self.minutesStep
        self.notes = notes
        self.range = range
    }

    public var budget: Duration { .seconds(minutes * 60) }

    public func drillOptions(on fretboard: Fretboard) -> DrillOptions {
        var options = DrillOptions()
        options.notes = notes
        options.frets = range.frets(on: fretboard)
        return options
    }
}
