import Testing
import TheoryCore
import PracticeCore

private let standard = Fretboard(tuning: .standard)
private let everyKey = Set(Key.appMajorKeys + Key.appMinorKeys)

private func picker(seed: UInt64 = 1, rerolls: Int = 0, history: [PastTheme] = []) -> ThemePicker {
    ThemePicker(day: "2026-09-30", seed: seed, rerolls: rerolls, history: history)
}

private func caged(_ number: Int) -> Position.ID { Position.ID(system: .caged, number: number) }

/// A session on a day in September.
private func past(_ day: Int, _ key: Key, _ number: Int = 1) -> PastTheme {
    PastTheme(day: "2026-09-\(day < 10 ? "0" : "")\(day)", theme: Theme(key: key, position: caged(number)))
}

/// The themes of many seeds.
private func themes(_ history: [PastTheme] = [], count: UInt64 = 300) -> [Theme] {
    (0..<count).map { picker(seed: $0, history: history).theme(on: standard, system: .caged) }
}

@Suite("Theme picker")
struct ThemePickerTests {
    @Test func theSameInputsGiveTheSameTheme() {
        let history = [past(29, .major(.c), 2)]
        #expect(themes(history) == themes(history))
    }

    @Test(arguments: [(Position.System.caged, 5), (.threeNotesPerString, 7)])
    func everyKeyAndPositionComesUp(system: Position.System, count: Int) {
        let year = (UInt64(739_000)..<739_365).map { picker(seed: $0).theme(on: standard, system: system) }
        #expect(Set(year.map(\.key)) == everyKey)
        #expect(Set(year.map(\.position)) == Set((1...count).map { Position.ID(system: system, number: $0) }))
    }

    @Test func keysFromTheLastSixDaysAreLeftOut() {
        // Seven days, some way apart; only C major's is too long ago.
        let keys: [Key] = [.major(.c), .minor(.a), .major(.f), .major(.g), .minor(.e), .major(.bFlat), .minor(.dSharp)]
        let history = keys.enumerated().map { past($0.offset * 4 + 1, $0.element) }
        #expect(Set(themes(history.reversed()).map(\.key)) == everyKey.subtracting(keys.dropFirst()))
    }

    @Test func positionsFromTheLastThreeDaysAreLeftOut() {
        let history = [past(1, .major(.c), 1), past(5, .major(.g), 2), past(6, .major(.d), 3), past(20, .major(.a), 4)]
        #expect(Set(themes(history).map(\.position)) == [caged(1), caged(5)])
    }

    @Test func severalSessionsOnOneDayCountAsOneDay() {
        let history = Array(repeating: past(20, .major(.g), 2), count: 8) + [past(1, .major(.c), 1)]
        #expect(!themes(history).contains { $0.key == .major(.c) || $0.position == caged(1) })
    }

    @Test func aDayWithNoThemeStillCounts() {
        let unthemed = (10..<16).map { PastTheme(day: "2026-09-\($0)", theme: nil) }
        let picked = themes(unthemed + [past(1, .major(.c), 1)])
        #expect(picked.contains { $0.key == .major(.c) })
        #expect(picked.contains { $0.position == caged(1) })
    }

    @Test func theDayItselfAndLaterDaysAreNotRecent() {
        let history = [past(30, .major(.c), 1), PastTheme(day: "2026-10-02", theme: Theme(key: .major(.g), position: caged(2)))]
        #expect(themes(history) == themes())
    }

    @Test func rerollsGiveANewKeyEachTimeAndAnotherPosition() {
        for seed in UInt64(0)..<50 {
            let themes = (0..<24).map { picker(seed: seed, rerolls: $0).theme(on: standard, system: .caged) }
            #expect(Set(themes.map(\.key)).count == 24)
            #expect(zip(themes, themes.dropFirst()).allSatisfy { $0.position != $1.position })
        }
    }

    /// Then the longest ago comes back first.
    @Test func excludedPositionsComeBackWhenThereAreNoOthers() {
        let history = [past(1, .major(.c), 1), past(2, .major(.g), 2), past(2, .major(.g), 3),
                       past(3, .major(.d), 4), past(3, .major(.d), 5)]
        #expect(Set(themes(history).map(\.position)) == [caged(1)])
    }
}

@Suite("Theme when the instrument changes")
struct ThemeRepickTests {
    @Test func aPositionThatStillExistsIsKept() {
        let theme = Theme(key: .major(.f), position: caged(3), stringSet: .dGB)
        let kept = picker().keepingKey(of: theme, on: standard, system: .caged)
        #expect(kept.position == theme.position && kept.stringSet == theme.stringSet)
        let dadgad = Fretboard(tuning: TuningPreset.dadgad.tuning, capo: 2)
        let keptOnDADGAD = picker().keepingKey(of: theme, on: dadgad, system: .caged)
        #expect(keptOnDADGAD.position == theme.position && keptOnDADGAD.stringSet == theme.stringSet)
    }

    @Test func anotherPositionSystemKeepsTheKeyAndComesBackToTheSamePosition() {
        for seed in UInt64(0)..<50 {
            let picker = picker(seed: seed, rerolls: 2)
            let theme = picker.theme(on: standard, system: .caged)
            let pattern = picker.keepingKey(of: theme, on: standard, system: .threeNotesPerString)
            #expect(pattern.key == theme.key)
            #expect(pattern.position.system == .threeNotesPerString)
            #expect(picker.keepingKey(of: pattern, on: standard, system: .caged) == theme)
        }
    }

    @Test func aCapoThatRemovesThePositionKeepsTheKey() {
        // F major's G shape ends at fret 13 at its lowest, so with the capo at 12 it would end at fret 25.
        let capo12 = Fretboard(tuning: .standard, capo: 12)
        let theme = Theme(key: .major(.f), position: caged(5))
        for seed in UInt64(0)..<50 {
            let kept = picker(seed: seed).keepingKey(of: theme, on: capo12, system: .caged)
            #expect(kept.key == .major(.f))
            #expect((1...4).contains(kept.position.number))
            #expect(kept == picker(seed: seed).keepingKey(of: theme, on: capo12, system: .caged))
        }
    }

    @Test(arguments: [TuningPreset.standard, .dropD, .dadgad, .openG], [0, 2, 12])
    func pickedPositionsExist(preset: TuningPreset, capo: Int) {
        let fretboard = Fretboard(tuning: preset.tuning, capo: capo)
        for system in Position.System.allCases {
            for seed in UInt64(0)..<30 {
                let theme = picker(seed: seed, history: (1...3).map { past($0, .major(.c), $0) }).theme(on: fretboard, system: system)
                #expect(theme.position(on: fretboard)?.id == theme.position)
            }
        }
    }

    /// A custom tuning can leave no position on the neck at all: the key still shows.
    @Test func noPositionFits() {
        let wild = Fretboard(tuning: Tuning([24, 29, 34, 39, 44, 72].map(Pitch.init)), capo: 12)
        for seed in UInt64(0)..<30 {
            let theme = picker(seed: seed).theme(on: wild, system: .threeNotesPerString)
            let exists = !wild.positions(of: theme.key.scale, system: .threeNotesPerString).isEmpty
            #expect((theme.position(on: wild) != nil) == exists)
            #expect(picker(seed: seed).keepingKey(of: theme, on: wild, system: .threeNotesPerString) == theme)
        }
    }

    @Test func namedByKeyAndPosition() {
        let theme = Theme(key: .major(.bFlat), position: caged(5))
        #expect(theme.key.description == "B♭ major")
        #expect(theme.position(on: standard)?.name == "G shape")
        #expect(theme.position(on: Fretboard(tuning: TuningPreset.dadgad.tuning))?.name == "Position 5")
    }
}

@Suite("Theme in a session's drills")
struct ThemedDrillTests {
    /// The first prompt of many runs: the share that are key notes, and every name.
    private func prompts(_ kind: DrillKind, notes: DrillOptions.Notes) -> (keyShare: Double, names: Set<String>) {
        let names = (UInt64(0)..<1000).compactMap { seed -> String? in
            var setup = DrillSetup(fretboard: standard, seed: seed)
            setup.options.notes = notes
            setup.follow(Theme(key: .major(.bFlat), position: caged(1)))
            var drill = kind.makeDrill(setup)
            drill.handle(.start(at: .zero))
            return drill.prompt?.noteName
        }
        let keyNotes: Set = ["B♭", "C", "D", "E♭", "F", "G", "A"]
        return (Double(names.filter(keyNotes.contains).count) / 1000, Set(names))
    }

    @Test(arguments: DrillKind.all.filter { $0.module == .notes })
    func spelledInTheKeyWithSeventyPercentKeyNotes(kind: DrillKind) {
        let all = prompts(kind, notes: .all)
        #expect((0.65...0.75).contains(all.keyShare))
        #expect(all.names == ["B♭", "C", "D", "E♭", "F", "G", "A", "B", "D♭", "E", "G♭", "A♭"])
        let naturals = prompts(kind, notes: .naturals)
        #expect((0.65...0.75).contains(naturals.keyShare))
        #expect(naturals.names == ["C", "D", "E", "F", "G", "A", "B"])
    }
}
