import TheoryCore

/// What a day's sessions are built around: a key, a position, a string set and a progression.
public struct Theme: Hashable, Sendable {
    /// One of the app's 24 keys.
    public var key: Key
    public var position: Position.ID
    /// What triads are played on. Nil where the key's chords have no voicing on the neck, or it hasn't been picked yet.
    public var stringSet: StringSet?
    /// What progression drills play: of the key's mode, with every chord in the position. Nil where none fits, or it
    /// hasn't been picked yet.
    public var progression: Progression?

    public init(key: Key, position: Position.ID, stringSet: StringSet? = nil, progression: Progression? = nil) {
        self.key = key
        self.position = position
        self.stringSet = stringSet
        self.progression = progression
    }

    /// The position as it is on a neck; nil when it isn't there.
    public func position(on fretboard: Fretboard) -> Position? {
        fretboard.positions(of: key.scale, system: position.system).first { $0.id == position }
    }
}

extension DrillSetup {
    /// How often a themed prompt is a note of the key.
    private static let keyNoteShare = 0.7

    /// Prompts are spelled in the theme's key and favour its notes. Its position is for scale and progression drills,
    /// its string set for triad drills, and its progression for progression drills.
    public mutating func follow(_ theme: Theme) {
        self.theme = theme
        key = theme.key
        weighting = NoteWeighting(preferred: Set(theme.key.notes.map(\.pitchClass)), share: Self.keyNoteShare)
        if let stringSet = theme.stringSet { options.stringSets = [stringSet] }
        options.progression = theme.progression
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
    /// A reroll gives what it replaces, so that the string set and the progression are others if there are any.
    public func theme(on fretboard: Fretboard, system: Position.System, replacing old: Theme? = nil) -> Theme {
        let recent = Set(recentDays.prefix(Self.keyDays).joined().map(\.key))
        var random = SplitMix64(seed: seed)
        let keys = random.shuffled(Key.appMajorKeys + Key.appMinorKeys).filter { !recent.contains($0) }
        let key = keys[rerolls % keys.count]
        // No position fits the neck: there is none to show.
        let position = pickPosition(in: key, on: fretboard, system: system) ?? Position.ID(system: system, number: 1)
        return Theme(key: key, position: position,
                     stringSet: pickStringSet(in: key, on: fretboard, replacing: old?.stringSet),
                     progression: pickProgression(in: key, at: position, on: fretboard, replacing: old?.progression))
    }

    /// A saved theme for the neck as it is now: the same key, with a position, a string set and a progression picked
    /// again where the old one won't do, or there is none yet.
    public func keepingKey(of theme: Theme, on fretboard: Fretboard, system: Position.System) -> Theme {
        var kept = theme
        if theme.position.system != system || theme.position(on: fretboard) == nil {
            kept.position = pickPosition(in: theme.key, on: fretboard, system: system) ?? theme.position
        }
        let keepsSet = theme.stringSet.map(stringSets(for: theme.key, on: fretboard).contains) ?? false
        if !keepsSet { kept.stringSet = pickStringSet(in: theme.key, on: fretboard) }
        let fitting = progressions(for: kept.key, at: kept.position, on: fretboard)
        if !(theme.progression.map(fitting.contains) ?? false) {
            kept.progression = pickProgression(from: fitting)
        }
        return kept
    }

    /// Of the key's mode, with every chord in the position, in the library's order. Empty where none fits.
    private func progressions(for key: Key, at id: Position.ID, on fretboard: Fretboard) -> [Progression] {
        guard let position = Theme(key: key, position: id).position(on: fretboard) else { return [] }
        let library = Progression.library(key.mode)
        // Each chord looked at once: several progressions share it.
        let chords = Set(library.flatMap { $0.chords(in: key) })
        let playable = chords.filter { !fretboard.voicings(of: $0, in: position).isEmpty }
        return library.filter { Set($0.chords(in: key)).isSubset(of: playable) }
    }

    /// The last practised day's is left out unless it is the only choice, and then the one to be replaced likewise.
    private func pickProgression(in key: Key, at position: Position.ID, on fretboard: Fretboard,
                                 replacing old: Progression? = nil) -> Progression? {
        pickProgression(from: progressions(for: key, at: position, on: fretboard), replacing: old)
    }

    private func pickProgression(from fitting: [Progression], replacing old: Progression? = nil) -> Progression? {
        let recent = Set(recentDays.first?.compactMap(\.progression) ?? [])
        // Other random numbers than the key's, the position's and the string set's, so that it doesn't follow them.
        var random = SplitMix64(seed: seed ^ 0x5052_4F47_5245_5353)
        var choices = random.shuffled(fitting)
        for leftOut in [recent, Set([old].compactMap { $0 })] {
            let others = choices.filter { !leftOut.contains($0) }
            if !others.isEmpty { choices = others }
        }
        return choices.isEmpty ? nil : choices[rerolls % choices.count]
    }

    /// Those that have the most of a key's chords: all of them, where possible. Empty where none has any.
    private func stringSets(for key: Key, on fretboard: Fretboard) -> [StringSet] {
        let counts = fretboard.stringSets.map { (set: $0, chords: fretboard.chordCount(of: key, on: $0)) }
        let most = counts.map(\.chords).max() ?? 0
        return most == 0 ? [] : counts.filter { $0.chords == most }.map(\.set)
    }

    /// The last practised day's is left out unless it is the only choice, and then the one to be replaced likewise.
    private func pickStringSet(in key: Key, on fretboard: Fretboard, replacing old: StringSet? = nil) -> StringSet? {
        let recent = Set(recentDays.first?.compactMap(\.stringSet) ?? [])
        // Other random numbers than the key's and the position's, so that it doesn't follow them.
        var random = SplitMix64(seed: ~seed)
        var choices = random.shuffled(stringSets(for: key, on: fretboard))
        for leftOut in [recent, Set([old].compactMap { $0 })] {
            let others = choices.filter { !leftOut.contains($0) }
            if !others.isEmpty { choices = others }
        }
        return choices.isEmpty ? nil : choices[rerolls % choices.count]
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
