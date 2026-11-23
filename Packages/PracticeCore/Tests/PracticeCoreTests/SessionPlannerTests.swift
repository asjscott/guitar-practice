import Testing
import TheoryCore
import PracticeCore

/// Kinds made up for these tests. Their drill plays string 6's frets in order, and can answer a typed name.
func kind(_ id: String, usesKeyboard: Bool = false) -> DrillKind {
    DrillKind(id: id, title: id, instructions: "", symbol: "", usesKeyboard: usesKeyboard, rules: ToyRules.self)
}

private let four = [kind("a"), kind("b"), kind("c"), kind("keys", usesKeyboard: true)]

private func plan(_ minutes: Int, day: Int, kinds: [DrillKind] = four) -> [SessionBlock] {
    SessionPlanner.plan(kinds.map { WeightedDrill($0) }, budget: s(Double(minutes) * 60), day: day)
}

@Suite("Session planner")
struct SessionPlannerTests {
    @Test(arguments: [(15, 225.0), (30, 450.0), (60, 900.0)])
    func fourEqualBlocks(minutes: Int, seconds: Double) {
        for day in 739_000..<739_030 {
            let blocks = plan(minutes, day: day)
            #expect(Set(blocks.map(\.kind.id)) == ["a", "b", "c", "keys"])
            #expect(blocks.map(\.length) == Array(repeating: s(seconds), count: 4))
        }
    }

    @Test func tenMinutesGivesThreeBlocksOf200Seconds() {
        for day in 739_000..<739_030 {
            let blocks = plan(10, day: day)
            #expect(Set(blocks.map(\.kind.id)).count == 3)
            #expect(blocks.map(\.length) == [s(200), s(200), s(200)])
        }
    }

    @Test func theDroppedDrillRotatesByDay() {
        let dropped = (739_000..<739_008).map { day in
            Set(four.map(\.id)).subtracting(plan(10, day: day).map(\.kind.id)).first ?? "none"
        }
        #expect(dropped == ["a", "b", "c", "keys", "a", "b", "c", "keys"])
    }

    @Test func twelveMinutesKeepsAllFourAtTheMinimum() {
        #expect(plan(12, day: 1).map(\.length) == Array(repeating: s(180), count: 4))
        #expect(plan(11, day: 1).count == 3)
    }

    @Test(arguments: [10, 30])
    func theKeyboardDrillIsFirstOrLastAndBothHappen(minutes: Int) {
        var first = 0, last = 0
        for day in 739_000..<739_060 {
            let blocks = plan(minutes, day: day)
            guard let place = blocks.firstIndex(where: \.kind.usesKeyboard) else { continue }
            #expect(place == 0 || place == blocks.count - 1)
            if place == 0 { first += 1 } else { last += 1 }
        }
        #expect(first > 10)
        #expect(last > 10)
    }

    @Test func theOrderFollowsTheDay() {
        #expect(plan(30, day: 739_000) == plan(30, day: 739_000))
        let orders = Set((739_000..<739_200).map { plan(30, day: $0).map(\.kind.id) })
        #expect(orders.count == 12)     // 3! orders of the rest, times first or last
    }

    @Test func sharesFollowTheWeights() {
        let kinds = [WeightedDrill(four[0], weight: 2), WeightedDrill(four[1]), WeightedDrill(four[2], weight: 0)]
        let blocks = SessionPlanner.plan(kinds, budget: s(900), day: 5)
        #expect(blocks.first { $0.kind.id == "a" }?.length == s(600))
        #expect(blocks.first { $0.kind.id == "b" }?.length == s(300))
        #expect(blocks.count == 2)
    }

    @Test func oneDrillGetsTheWholeBudgetAndNoneGivesNoBlocks() {
        #expect(plan(10, day: 3, kinds: [four[1]]).map(\.length) == [s(600)])
        #expect(plan(10, day: 3, kinds: []).isEmpty)
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
