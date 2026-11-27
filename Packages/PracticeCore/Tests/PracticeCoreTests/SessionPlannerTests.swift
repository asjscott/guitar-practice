import Testing
import TheoryCore
import PracticeCore

/// Kinds made up for these tests. Their drill plays string 6's frets in order, and can answer a typed name.
func kind(_ id: String, module: DrillModule = .notes, usesKeyboard: Bool = false, needsSound: Bool = false) -> DrillKind {
    var traits: DrillKind.Traits = []
    if usesKeyboard { traits.insert(.usesKeyboard) }
    if needsSound { traits.insert(.needsSound) }
    return DrillKind(id: id, module: module, title: id, instructions: "", symbol: "", traits: traits, rules: ToyRules.self)
}

private let notes = [kind("a"), kind("b"), kind("c"), kind("keys", usesKeyboard: true)]
private let scales = [kind("s1", module: .scales), kind("s2", module: .scales)]
private let triads = [kind("t1", module: .triads), kind("t2", module: .triads)]

private let days = 739_000..<739_060

private func plan(_ minutes: Int, day: Int, kinds: [DrillKind] = notes + scales + triads) -> [SessionBlock] {
    SessionPlanner.plan(kinds, budget: s(Double(minutes) * 60), day: day)
}

/// The lengths of each module's blocks, in the order they come, in whole seconds.
private func lengths(_ blocks: [SessionBlock]) -> [DrillModule: [Int]] {
    Dictionary(grouping: blocks, by: \.kind.module).mapValues { $0.map { Int($0.length / .seconds(1)) } }
}

@Suite("Session planner")
struct SessionPlannerTests {
    @Test(arguments: [10, 15, 30, 60])
    func modulesComeInOrderWhateverOrderTheDrillsAreIn(minutes: Int) {
        for day in days {
            let modules = plan(minutes, day: day, kinds: triads + scales + notes).map(\.kind.module)
            let inOrder = [DrillModule.notes, .scales, .triads].flatMap { module in modules.filter { $0 == module } }
            #expect(modules == inOrder)
            #expect(Set(modules).count == 3)
        }
    }

    // 15 : 20 : 20 of 600, 900, 1800 and 3600 s.
    @Test(arguments: [
        (10, [163], [218], [218]),
        (15, [122, 122], [327], [327]),
        (30, [122, 122, 122, 122], [327, 327], [327, 327]),
        (60, [245, 245, 245, 245], [654, 654], [654, 654]),
    ])
    func eachModuleTakesAsManyDrillsAsFitItsMinimum(minutes: Int, notes: [Int], scales: [Int], triads: [Int]) {
        for day in days {
            let blocks = plan(minutes, day: day)
            #expect(lengths(blocks) == [.notes: notes, .scales: scales, .triads: triads])
            #expect(Set(blocks.map(\.kind)).count == blocks.count)
        }
    }

    @Test(arguments: [10, 15, 30, 60])
    func theBlocksFillTheBudget(minutes: Int) {
        let total = plan(minutes, day: 5).map { $0.length / .seconds(1) }.reduce(0, +)
        #expect(abs(total - Double(minutes) * 60) < 0.1)
    }

    @Test func aMissingModulesTimeIsSharedByTheRest() {
        #expect(lengths(plan(35, day: 1, kinds: notes + triads)) == [.notes: [225, 225, 225, 225], .triads: [600, 600]])
        #expect(lengths(plan(10, day: 1, kinds: scales + triads)) == [.scales: [300], .triads: [300]])
        #expect(lengths(plan(12, day: 1, kinds: scales + triads)) == [.scales: [180, 180], .triads: [180, 180]])
    }

    @Test(arguments: [(10, 150.0), (15, 225.0), (30, 450.0), (60, 900.0)])
    func notesAloneGiveFourEqualBlocks(minutes: Int, seconds: Double) {
        for day in days {
            let blocks = plan(minutes, day: day, kinds: notes)
            #expect(Set(blocks.map(\.kind.id)) == ["a", "b", "c", "keys"])
            #expect(blocks.map(\.length) == Array(repeating: s(seconds), count: 4))
        }
    }

    @Test func drillsExactlyAtTheMinimumFit() {
        #expect(plan(6, day: 1, kinds: notes).map(\.length) == Array(repeating: s(90), count: 4))
        #expect(plan(6, day: 1, kinds: scales).map(\.length) == [s(180), s(180)])
        #expect(plan(5, day: 1, kinds: notes).count == 3)
        #expect(plan(5, day: 1, kinds: scales).count == 1)
    }

    @Test func atTenMinutesEveryDrillHasItsTurnByDay() {
        func kept(_ module: DrillModule) -> [String] {
            (739_000..<739_008).flatMap { plan(10, day: $0).filter { $0.kind.module == module }.map(\.kind.id) }
        }
        #expect(kept(.notes) == ["keys", "a", "b", "c", "keys", "a", "b", "c"])
        #expect(kept(.scales) == ["s2", "s1", "s2", "s1", "s2", "s1", "s2", "s1"])
        #expect(kept(.triads) == ["t2", "t1", "t2", "t1", "t2", "t1", "t2", "t1"])
    }

    @Test func atFifteenMinutesNoNotesDrillIsLeftOutForMoreThanTwoDays() {
        for day in days {
            let three = (day..<day + 3).flatMap { plan(15, day: $0) }.map(\.kind)
            #expect(Set(notes).isSubset(of: three))
        }
    }

    @Test(arguments: [15, 30])
    func theKeyboardDrillIsFirstOrLastInItsModuleAndBothHappen(minutes: Int) {
        var first = 0, last = 0
        for day in days {
            let blocks = plan(minutes, day: day).filter { $0.kind.module == .notes }
            guard let place = blocks.firstIndex(where: \.kind.usesKeyboard) else { continue }
            #expect(place == 0 || place == blocks.count - 1)
            if place == 0 { first += 1 } else { last += 1 }
        }
        #expect(first > 5)
        #expect(last > 5)
    }

    @Test func theOrderFollowsTheDay() {
        #expect(plan(30, day: 739_000) == plan(30, day: 739_000))
        let plans = (739_000..<739_200).map { plan(30, day: $0).map(\.kind) }
        func orders(_ module: DrillModule) -> Int { Set(plans.map { $0.filter { $0.module == module }.map(\.id) }).count }
        #expect(orders(.notes) == 12)     // 3! orders of the rest, times first or last
        #expect(orders(.scales) == 2)
        #expect(orders(.triads) == 2)
    }

    // 15 : 20 : 20 : 20 of 600, 900, 1800 and 3600 s.
    private static let fourModuleLengths: [(minutes: Int, lengths: [DrillModule: [Int]])] = [
        (10, [.notes: [120], .scales: [160], .triads: [160], .progressions: [160]]),
        (15, [.notes: [90, 90], .scales: [240], .triads: [240], .progressions: [240]]),
        (30, [.notes: [90, 90, 90, 90], .scales: [240, 240], .triads: [240, 240], .progressions: [240, 240]]),
        (60, [.notes: [180, 180, 180, 180], .scales: [480, 480], .triads: [480, 480], .progressions: [320, 320, 320]]),
    ]

    @Test(arguments: 0..<4)
    func withProgressionsFourModulesShareTheTime(index: Int) {
        let (minutes, expected) = Self.fourModuleLengths[index]
        for day in days {
            let blocks = plan(minutes, day: day, kinds: Self.fourModules)
            #expect(lengths(blocks) == expected)
            let modules = blocks.map(\.kind.module).reduce(into: [DrillModule]()) { if $0.last != $1 { $0.append($1) } }
            #expect(modules == [.notes, .scales, .triads, .progressions])
            #expect(abs(blocks.map { $0.length / .seconds(1) }.reduce(0, +) - Double(minutes) * 60) < 0.1)
        }
    }

    private static let progressions = ["p1", "p2", "p3"].map { kind($0, module: .progressions) }
    /// In no particular order.
    private static let fourModules = progressions + triads + scales + notes

    @Test func progressionDrillsHaveTheirTurnByDay() {
        let kept = (739_000..<739_006).flatMap {
            plan(10, day: $0, kinds: notes + Self.progressions).filter { $0.kind.module == .progressions }.map(\.kind.id)
        }
        #expect(Set(kept.prefix(3)) == ["p1", "p2", "p3"])
        #expect(Array(kept.prefix(3)) == Array(kept.suffix(3)))
    }

    @Test func oneDrillGetsTheWholeBudgetAndNoneGivesNoBlocks() {
        #expect(plan(10, day: 3, kinds: [notes[1]]).map(\.length) == [s(600)])
        #expect(plan(10, day: 3, kinds: []).isEmpty)
    }
}

@Suite("Session planner: which drills")
struct SessionPlannerDrillsTests {
    private let setup = DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1)

    @Test func withoutSoundHearFindItIsLeftOutAndTheRestShareTheTime() {
        let kinds = SessionPlanner.drills(from: DrillKind.all, for: setup, hasSound: false)
        #expect(kinds == [.notePlayIt, .allInstances, .fretNameIt, .upAndDown, .fromADegree, .triadPlayIt, .inversions])
        #expect(plan(15, day: 1, kinds: kinds.filter { $0.module == .notes }).map(\.length) == [s(300), s(300), s(300)])
        #expect(SessionPlanner.noSoundNotice(from: DrillKind.all)
                == "No sound: Hear → find it is left out, and chimes flash.")
    }

    @Test func withoutSoundAndNoDrillThatNeedsItOnlyChimesChange() {
        #expect(SessionPlanner.noSoundNotice(from: [kind("in")]) == "No sound: chimes flash.")
    }

    @Test func aSessionCantStartWhenNoDrillCanPromptAnything() {
        var setup = setup
        setup.options.frets = 0...0     // nothing for Hear → find it
        #expect(SessionPlanner.nothingToPromptReason(from: [.hearFindIt], for: setup, hasSound: true) != nil)
        #expect(SessionPlanner.nothingToPromptReason(from: [.hearFindIt, kind("in")], for: setup, hasSound: true) == nil)
    }

    @Test func withSoundEveryDrillIsInButTheCircleDrills() {
        var setup = setup
        setup.options.progression = Progression.named("I–IV–V")
        #expect(SessionPlanner.drills(from: DrillKind.all, for: setup, hasSound: true)
                == DrillKind.all.filter { !$0.goesRoundTheCircle })
    }

    @Test func progressionDrillsAreLeftOutWithoutAProgression() {
        #expect(SessionPlanner.drills(from: DrillKind.all, for: setup, hasSound: true)
                == DrillKind.all.filter { $0.module != .progressions && !$0.goesRoundTheCircle })
    }

    @Test func triadsWithNoVoicingInRangeAreLeftOutAndSetupSaysWhy() {
        var setup = setup
        #expect(SessionPlanner.noTriadsNotice(from: DrillKind.all, for: setup) == nil)
        setup.follow(Theme(key: .major(.c), position: .init(system: .caged, number: 1), stringSet: .dGB))
        #expect(SessionPlanner.noTriadsNotice(from: DrillKind.all, for: setup) == nil)
        setup.options.frets = 1...1
        #expect(SessionPlanner.noTriadsNotice(from: DrillKind.all, for: setup)
                == "Triads are left out: no voicing of the key’s chords on D-G-B fits these frets.")
        #expect(SessionPlanner.noTriadsNotice(from: [.notePlayIt], for: setup) == nil)
        let kinds = SessionPlanner.drills(from: DrillKind.all, for: setup, hasSound: true)
        #expect(!kinds.contains { $0.module == .triads })
        let total = SessionPlanner.plan(kinds, budget: s(900), day: 1).map { $0.length / .seconds(1) }.reduce(0, +)
        #expect(abs(total - 900) < 0.1)
    }

    @Test func progressionsWithNoneInTheThemeAreLeftOutAndSetupSaysWhy() {
        var setup = setup
        let eShape = Position.ID(system: .caged, number: CAGEDShape.e.number)
        setup.follow(Theme(key: .major(.g), position: eShape, stringSet: .dGB, progression: Progression.named("I–IV–V")))
        #expect(SessionPlanner.noProgressionsNotice(from: DrillKind.all, for: setup) == nil)
        #expect(SessionPlanner.drills(from: DrillKind.all, for: setup, hasSound: true).contains(.nearestVoicing))
        setup.follow(Theme(key: .major(.g), position: eShape, stringSet: .dGB))
        #expect(SessionPlanner.noProgressionsNotice(from: DrillKind.all, for: setup)
                == "Progressions are left out: no progression in G major has every chord in the E shape.")
        #expect(SessionPlanner.noProgressionsNotice(from: [.notePlayIt], for: setup) == nil)
        #expect(!SessionPlanner.drills(from: DrillKind.all, for: setup, hasSound: true).contains { $0.module == .progressions })
    }

    @Test func aDrillWithNothingToPromptIsLeftOut() {
        var setup = setup
        setup.options.frets = 0...0     // no target above the open string for Hear → find it
        #expect(SessionPlanner.drills(from: DrillKind.all, for: setup, hasSound: true)
                == [.notePlayIt, .allInstances, .fretNameIt, .upAndDown, .fromADegree, .triadPlayIt])      // open strings make triads, but no climb
    }
}

@Suite("Session setup")
struct SessionSetupTests {
    @Test(arguments: [(0, 0...12), (3, 3...15), (10, 10...22), (11, 11...22), (12, 12...22)])
    func first12FretsCountFromTheCapo(capo: Int, frets: ClosedRange<Int>) {
        #expect(SessionRange.first12.frets(on: Fretboard(tuning: .standard, capo: capo)) == frets)
    }

    @Test(arguments: [(0, 0...22), (5, 5...22), (12, 12...22)])
    func wholeNeckIsCapoTo22(capo: Int, frets: ClosedRange<Int>) {
        #expect(SessionRange.wholeNeck.frets(on: Fretboard(tuning: .standard, capo: capo)) == frets)
    }

    @Test func optionsForDrills() {
        let options = SessionSetup(minutes: 20, notes: .all, range: .first12)
            .drillOptions(on: Fretboard(tuning: .standard, capo: 4))
        #expect(options.notes == .all)
        #expect(options.frets == 4...16)
        #expect(options.strings == nil)
        #expect(options.order == .random)
    }

    @Test func minutesStayBetween10And60InStepsOf5() {
        #expect([-5, 9, 10, 17, 18, 60, 99].map { SessionSetup(minutes: $0).minutes } == [10, 10, 10, 15, 20, 60, 60])
        #expect(SessionSetup().minutes == 15)
        #expect(SessionSetup().budget == s(900))
    }
}

@Suite("Modules")
struct DrillModuleTests {
    @Test func everyDrillSoFarIsInFretboardNotesWithItsSavedID() {
        let notes = DrillKind.all.filter { $0.module == .notes }
        #expect(notes.map(\.id) == ["notePlayIt", "allInstances", "noteCircle", "hearFindIt", "fretNameIt"])
        #expect(DrillModule.allCases.map(\.title) == ["Fretboard notes", "Scales in position", "Triads", "Progressions"])
    }

    @Test func groupsKeepTheModulesOrderAndLeaveOutEmptyOnes() {
        let groups = DrillModule.groups(of: [triads[0], notes[0], triads[1]], by: \.module)
        #expect(groups.map(\.module) == [.notes, .triads])
        #expect(groups.map(\.members) == [[notes[0]], triads])
    }
}
