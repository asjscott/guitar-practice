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

private let notes = [kind("a"), kind("b")]
private let triads = [kind("t1", module: .triads), kind("t2", module: .triads)]

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
        let options = SessionSetup(notes: .all, range: .first12)
            .drillOptions(on: Fretboard(tuning: .standard, capo: 4))
        #expect(options.notes == .all)
        #expect(options.frets == 4...16)
        #expect(options.strings == nil)
        #expect(options.order == .random)
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
