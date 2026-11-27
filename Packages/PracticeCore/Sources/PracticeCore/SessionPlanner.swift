/// A planned block: one drill and how long it is meant to last.
public struct SessionBlock: Hashable, Sendable {
    public let kind: DrillKind
    public let length: Duration

    public init(kind: DrillKind, length: Duration) {
        self.kind = kind
        self.length = length
    }
}

/// Splits a session's time into blocks.
public enum SessionPlanner {
    /// The drills a session can use: those with something to prompt and, without sound, that don't need it.
    public static func drills(from kinds: [DrillKind], for setup: DrillSetup, hasSound: Bool) -> [DrillKind] {
        kinds.filter { canUse($0, hasSound: hasSound) && $0.makeDrill(setup).nothingToPromptReason == nil }
    }

    /// What a session without sound does differently.
    public static func noSoundNotice(from kinds: [DrillKind]) -> String {
        let leftOut = kinds.filter(\.needsSound).map(\.title)
        guard !leftOut.isEmpty else { return "No sound: chimes flash." }
        return "No sound: \(leftOut.joined(separator: ", ")) \(leftOut.count == 1 ? "is" : "are") left out, and chimes flash."
    }

    /// Why a session has no triads, when no voicing is in range; nil when it has some.
    public static func noTriadsNotice(from kinds: [DrillKind], for setup: DrillSetup) -> String? {
        let triads = kinds.filter { $0.module == .triads }
        guard !triads.isEmpty, drills(from: triads, for: setup, hasSound: true).isEmpty else { return nil }
        let sets = setup.fretboard.stringSets.filter(setup.options.stringSets.contains).map(\.name)
        return "Triads are left out: no voicing of the key’s chords on \(sets.joined(separator: ", ")) fits these frets."
    }

    /// Why a session has no progressions, when the theme has none; nil when it has one.
    public static func noProgressionsNotice(from kinds: [DrillKind], for setup: DrillSetup) -> String? {
        let progressions = kinds.filter { $0.module == .progressions }
        guard !progressions.isEmpty, drills(from: progressions, for: setup, hasSound: true).isEmpty else { return nil }
        guard setup.options.progression == nil, let position = setup.progressionPosition else {
            return progressions[0].makeDrill(setup).nothingToPromptReason.map { "Progressions are left out: \($0)" }
        }
        return "Progressions are left out: no progression in \(setup.chosenKey) has every chord in the \(position.name)."
    }

    /// Why a session can't prompt anything; nil when one of its drills can.
    public static func nothingToPromptReason(from kinds: [DrillKind], for setup: DrillSetup, hasSound: Bool) -> String? {
        let reasons = kinds.filter { canUse($0, hasSound: hasSound) }.map { $0.makeDrill(setup).nothingToPromptReason }
        return reasons.contains(nil) ? nil : reasons.compactMap { $0 }.first
    }

    /// Circle drills aren't timed blocks: they wait for the daily routine (spec #64).
    private static func canUse(_ kind: DrillKind, hasSound: Bool) -> Bool {
        (hasSound || !kind.needsSound) && !kind.goesRoundTheCircle
    }

    /// Modules in order, with time by weight; each takes as many of its drills as fit its minimum, at least one, in
    /// equal parts. `day` is a count of calendar days: it says which drills are left out, and seeds the order.
    public static func plan(_ drills: [DrillKind], budget: Duration, day: Int) -> [SessionBlock] {
        var random = SplitMix64(seed: UInt64(bitPattern: Int64(day)))
        let groups = DrillModule.groups(of: drills, by: \.module)
        let totalWeight = groups.map(\.module.weight).reduce(0, +)
        return groups.flatMap { group in
            let share = budget * group.module.weight / totalWeight
            let count = min(max(1, Int(share / group.module.minimumLength)), group.members.count)
            let length = share / count
            return shuffled(rotated(group.members, keeping: count, day: day), random: &random)
                .map { SessionBlock(kind: $0, length: length) }
        }
    }

    /// Some of the drills, starting one later each day; in the given order, so that the shuffle doesn't follow the
    /// rotation.
    private static func rotated(_ drills: [DrillKind], keeping count: Int, day: Int) -> [DrillKind] {
        let first = (day % drills.count + drills.count) % drills.count
        let kept = (drills[first...] + drills[..<first]).suffix(count)
        return drills.filter { kept.contains($0) }
    }

    /// Any drill that uses the keyboard is first or last, so that the player changes between keyboard and guitar at
    /// most once.
    private static func shuffled(_ drills: [DrillKind], random: inout SplitMix64) -> [DrillKind] {
        let drills = random.shuffled(drills)
        let keyboard = drills.filter(\.usesKeyboard)
        let guitar = drills.filter { !$0.usesKeyboard }
        return random.next().isMultiple(of: 2) ? keyboard + guitar : guitar + keyboard
    }
}
