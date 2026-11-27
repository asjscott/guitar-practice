import TheoryCore

/// A planned block: one drill, what it is made from and when it ends.
public struct SessionBlock: Hashable, Sendable {
    /// When a block is over.
    public enum End: Hashable, Sendable {
        /// Chimes 30 s before its planned length and at it (Extend moves both); it goes on until the player moves on.
        case planned(Duration)
        /// When its drill is done: it stops by itself, with a chime. Free time never is.
        case whenDone
        /// When the time through numbered this (from 1) ends, with the chime that waits for it.
        case afterTimesThrough(Int)
    }

    public let kind: DrillKind
    public let end: End
    /// The block's own setup, in place of the session's; nil = the session's.
    public let setup: DrillSetup?
    /// Planned but not played: the session passes over it.
    public let isLeftOut: Bool

    public init(kind: DrillKind, end: End, setup: DrillSetup? = nil, isLeftOut: Bool = false) {
        self.kind = kind
        self.end = end
        self.setup = setup
        self.isLeftOut = isLeftOut
    }

    /// A block with a planned length.
    public init(kind: DrillKind, length: Duration) {
        self.init(kind: kind, end: .planned(length))
    }

    /// Nil unless it has a planned length.
    public var length: Duration? {
        if case .planned(let length) = end { length } else { nil }
    }
}

/// A day's session: the routine's eight blocks, some perhaps left out, and why.
public struct SessionRoutine: Hashable, Sendable {
    /// The eight steps in order, those left out included.
    public let blocks: [SessionBlock]
    /// For setup: what is left out, and what goes differently.
    public let notices: [String]

    /// Why the session can't start: every step is left out. Nil when one can run.
    public var nothingToPromptReason: String? {
        blocks.contains { !$0.isLeftOut } ? nil : notices.last ?? "Nothing in the session can be played."
    }
}

/// Plans the daily routine (spec #64): the same eight steps every day, from the theme.
public enum SessionPlanner {
    /// Step 2's planned length.
    public static let noteDrillLength: Duration = .seconds(120)
    /// Step 4's.
    public static let shortFocusLength: Duration = .seconds(60)
    /// Stay in position goes through the progression at least this often.
    public static let minimumTimesThrough = 4

    /// The eight blocks, from a setup that follows the day's theme (`DrillSetup.follow`):
    ///
    /// 1. Note circle; 2. a note drill by day (`noteDrill(day:hasSound:hearFindItUnlocked:)`), 2 minutes; 3. Scale circle;
    /// 4. Up and down in the theme's scale and position alone, 1 minute; 5. Triad circle on the theme's string set, or
    /// where that can't go round, on another; 6. Chords in position; 7. Stay in position, until every voicing of every
    /// chord in the position has come up and at least 4 times through; 8. Free time.
    ///
    /// Without sound, or without a progression, steps 6–8 are left out; so is any step with nothing to prompt. `day`
    /// is a count of calendar days. Circle steps are set against `circleBests`.
    public static func routine(for setup: DrillSetup, day: Int, hasSound: Bool, hearFindItUnlocked: Bool,
                               circleBests: [DrillKind: CircleResult] = [:]) -> SessionRoutine {
        var notices: [String] = []
        let progressionProblem = setup.progressionProblem
        if !hasSound {
            notices.append(progressionProblem == nil
                ? "No sound: \(listed(progressionSteps.map(\.title))) are left out, and chimes flash."
                : "No sound: chimes flash.")
        }
        if let progressionProblem {
            notices.append("Progressions are left out: " + progressionNotice(for: setup, problem: progressionProblem))
        }
        let steps: [(DrillKind, SessionBlock.End, DrillSetup)] = [
            (.noteCircle, .whenDone, setup),
            (noteDrill(day: day, hasSound: hasSound, hearFindItUnlocked: hearFindItUnlocked), .planned(noteDrillLength),
             setup),
            (.scaleCircle, .whenDone, setup),
            (.upAndDown, .planned(shortFocusLength), themesScaleOnly(setup)),
            (.triadCircle, .whenDone, triadCircleSetup(setup)),
            (.chordsInPosition, .whenDone, setup),
            (.stayInPosition, .afterTimesThrough(timesThrough(of: setup)), setup),
            (.freeTime, .whenDone, setup),
        ]
        let blocks = steps.map { kind, end, stepSetup in
            var stepSetup = stepSetup
            stepSetup.circleBest = circleBests[kind]
            var isLeftOut = false
            if progressionSteps.contains(kind), !hasSound || progressionProblem != nil {
                isLeftOut = true
            } else if let reason = kind.makeDrill(stepSetup).nothingToPromptReason {
                isLeftOut = true
                notices.append("\(kind.title) is left out: \(reason)")
            }
            return SessionBlock(kind: kind, end: end, setup: stepSetup, isLeftOut: isLeftOut)
        }
        return SessionRoutine(blocks: blocks, notices: notices)
    }

    /// Steps 6–8.
    private static let progressionSteps: [DrillKind] = [.chordsInPosition, .stayInPosition, .freeTime]

    /// Step 2: Note → play it on even days, Fret → name it on odd ones; once Hear → find it is unlocked, it takes every
    /// third day, if there is sound.
    public static func noteDrill(day: Int, hasSound: Bool, hearFindItUnlocked: Bool) -> DrillKind {
        if hearFindItUnlocked, hasSound, day.isMultiple(of: 3) { return .hearFindIt }
        return day.isMultiple(of: 2) ? .notePlayIt : .fretNameIt
    }

    /// Whether Hear → find it joins step 2: the last 3 complete Note circles (oldest first) had no wrong notes.
    public static func unlocksHearFindIt(noteCircles: [CircleResult]) -> Bool {
        let last = noteCircles.filter(\.isComplete).suffix(3)
        return last.count == 3 && last.allSatisfy { $0.wrongNotes == 0 }
    }

    /// How long a session takes: the median of past ones (Free time left out), once there are three.
    public static func estimate(from past: [Duration]) -> Duration? {
        guard past.count >= 3 else { return nil }
        let sorted = past.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Up and down through the theme's own scale, not each of its mode's in turn.
    private static func themesScaleOnly(_ setup: DrillSetup) -> DrillSetup {
        guard let theme = setup.theme else { return setup }
        var only = setup
        only.theme = nil
        only.key = theme.key
        only.options.key = theme.key
        only.options.scaleKind = theme.key.scale.kind
        only.options.positionSystem = theme.position.system
        only.options.position = theme.position
        return only
    }

    /// The theme's string set, or where not every key's triad has two voicings on it, every set: the drill climbs the
    /// first that holds them.
    private static func triadCircleSetup(_ setup: DrillSetup) -> DrillSetup {
        guard DrillKind.triadCircle.makeDrill(setup).nothingToPromptReason != nil else { return setup }
        var other = setup
        other.options.stringSets = Set(setup.fretboard.stringSets)
        return other
    }

    /// Enough times through for every chord's every voicing in the position to come up, and at least 4.
    private static func timesThrough(of setup: DrillSetup) -> Int {
        guard let progression = setup.options.progression, let position = setup.progressionPosition else {
            return minimumTimesThrough
        }
        let most = progression.chords(in: setup.chosenKey).map { setup.fretboard.voicings(of: $0, in: position).count }
            .max() ?? 0
        return max(minimumTimesThrough, most)
    }

    private static func progressionNotice(for setup: DrillSetup, problem: String) -> String {
        guard setup.options.progression == nil, let position = setup.progressionPosition else { return problem }
        return "no progression in \(setup.chosenKey) has every chord in the \(position.name)."
    }

    /// "A, B and C".
    private static func listed(_ names: [String]) -> String {
        names.count < 2 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
}
