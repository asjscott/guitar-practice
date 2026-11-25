import TheoryCore

/// What a day's sessions are built around: a key and a position.
public struct Theme: Hashable, Sendable {
    /// One of the app's 24 keys.
    public var key: Key
    public var position: Position.ID

    public init(key: Key, position: Position.ID) {
        self.key = key
        self.position = position
    }

    /// The position as it is on a neck; nil when it isn't there.
    public func position(on fretboard: Fretboard) -> Position? {
        fretboard.positions(of: key.scale, system: position.system).first { $0.id == position }
    }
}

extension DrillSetup {
    /// How often a themed prompt is a note of the key.
    private static let keyNoteShare = 0.7

    /// Prompts are spelled in the theme's key and favour its notes. Its position is for scale drills only.
    public mutating func follow(_ theme: Theme) {
        self.theme = theme
        key = theme.key
        weighting = NoteWeighting(preferred: Set(theme.key.notes.map(\.pitchClass)), share: Self.keyNoteShare)
    }
}

/// A started session, as the picker sees it.
public struct PastTheme: Hashable, Sendable {
    /// The day it started, "2026-07-25".
    public let day: String
    /// Nil for a session without a theme: its day still counts as one.
    public let theme: Theme?

    public init(day: String, theme: Theme?) {
        self.day = day
        self.theme = theme
    }
}

/// Picks a day's theme: the same inputs always give the same one.
public struct ThemePicker: Sendable {
    /// How many days with a started session a key, or a position, is left out for.
    static let keyDays = 6, positionDays = 3

    private let seed: UInt64
    private let rerolls: Int
    /// The themes of each recent day with a started session, newest day first.
    private let recentDays: [[Theme]]

    /// `day` is like "2026-07-25" and `seed` comes from it. `history` may be in any order; sessions on the day itself
    /// or later are ignored.
    public init(day: String, seed: UInt64, rerolls: Int = 0, history: [PastTheme]) {
        self.seed = seed
        self.rerolls = rerolls
        let days = Dictionary(grouping: history.filter { $0.day < day }, by: \.day)
        recentDays = days.sorted { $0.key > $1.key }.prefix(max(Self.keyDays, Self.positionDays))
            .map { $0.value.compactMap(\.theme) }
    }

    /// The day's theme on a neck. Its position is the lowest placement of a shape or pattern of the key's own scale.
    public func theme(on fretboard: Fretboard, system: Position.System) -> Theme {
        let recent = Set(recentDays.prefix(Self.keyDays).joined().map(\.key))
        var random = SplitMix64(seed: seed)
        let keys = random.shuffled(Key.appMajorKeys + Key.appMinorKeys).filter { !recent.contains($0) }
        let key = keys[rerolls % keys.count]
        return Theme(key: key, position: pickPosition(in: key, on: fretboard, system: system)
            // No position fits the neck: there is none to show.
            ?? Position.ID(system: system, number: 1))
    }

    /// A saved theme for the neck as it is now: itself if its position is still there, or the key with another.
    public func keepingKey(of theme: Theme, on fretboard: Fretboard, system: Position.System) -> Theme {
        if theme.position.system == system, theme.position(on: fretboard) != nil { return theme }
        guard let position = pickPosition(in: theme.key, on: fretboard, system: system) else { return theme }
        return Theme(key: theme.key, position: position)
    }

    /// Recent ones are left out, unless no others exist; then the longest ago come back first.
    private func pickPosition(in key: Key, on fretboard: Fretboard, system: Position.System) -> Position.ID? {
        let existing = fretboard.positions(of: key.scale, system: system).map(\.id).filter { $0.octave == 0 }
            .sorted { $0.number < $1.number }
        var random = SplitMix64(seed: seed)
        let shuffled = random.shuffled(existing)
        for days in (0...Self.positionDays).reversed() {
            let recent = Set(recentDays.prefix(days).joined().map(\.position))
            let choices = shuffled.filter { !recent.contains($0) }
            if !choices.isEmpty { return choices[rerolls % choices.count] }
        }
        return nil
    }
}
