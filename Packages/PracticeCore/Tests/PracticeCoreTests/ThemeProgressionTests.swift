import Testing
import TheoryCore
import PracticeCore

private let standard = Fretboard(tuning: .standard)

private func picker(seed: UInt64 = 1, rerolls: Int = 0, history: [PastTheme] = []) -> ThemePicker {
    ThemePicker(day: "2026-09-30", seed: seed, rerolls: rerolls, history: history)
}

private func caged(_ number: Int) -> Position.ID { Position.ID(system: .caged, number: number) }

private func named(_ id: String) -> Progression { Progression.named(id)! }

private func past(_ day: String, _ progression: String?) -> PastTheme {
    PastTheme(day: day, theme: Theme(key: .major(.c), position: caged(1), stringSet: .dGB,
                                     progression: progression.map(named)))
}

/// Whether a theme's progression is of its key's mode, with every chord in its position.
private func fits(_ theme: Theme, on fretboard: Fretboard) -> Bool {
    guard let progression = theme.progression, let position = theme.position(on: fretboard) else { return false }
    return progression.mode == theme.key.mode && fretboard.fits(progression, in: theme.key, position: position)
}

@Suite("Theme's progression")
struct ThemeProgressionTests {
    @Test func everyProgressionComesUpInStandardTuningAndAlwaysFits() {
        let themes = (UInt64(0)..<100).map { picker(seed: $0).theme(on: standard, system: .caged) }
        for theme in themes { #expect(fits(theme, on: standard)) }
        #expect(Set(themes.compactMap(\.progression)) == Set(Progression.library))
    }

    @Test(arguments: [TuningPreset.dadgad, .openG], [0, 2])
    func inOpenTuningsSomeThemesLeaveProgressionsOut(preset: TuningPreset, capo: Int) {
        let fretboard = Fretboard(tuning: preset.tuning, capo: capo)
        var leftOut: Set<Progression> = []
        for seed in UInt64(0)..<40 {
            let theme = picker(seed: seed).theme(on: fretboard, system: .caged)
            guard let position = theme.position(on: fretboard) else { continue }
            let fitting = Progression.library(theme.key.mode).filter { fretboard.fits($0, in: theme.key, position: position) }
            leftOut.formUnion(Progression.library(theme.key.mode).filter { !fitting.contains($0) })
            if fitting.isEmpty { #expect(theme.progression == nil) } else { #expect(fits(theme, on: fretboard)) }
        }
        #expect(!leftOut.isEmpty)
    }

    @Test func theLastPractisedDaysIsLeftOut() {
        func progressions(_ history: [PastTheme]) -> Set<String> {
            Set((UInt64(0)..<120).compactMap {
                let theme = picker(seed: $0, history: history).theme(on: standard, system: .caged)
                return theme.key.mode == .major ? theme.progression?.id : nil
            })
        }
        let all = Set(Progression.library(.major).map(\.id))
        #expect(progressions([past("2026-09-03", "I–IV–V"), past("2026-09-01", "ii–V–I")])
                == all.subtracting(["I–IV–V"]))
        #expect(progressions([past("2026-09-30", "I–IV–V")]) == all)
    }

    @Test func unlessItIsTheOnlyOne() throws {
        var checked = 0
        for fretboard in [Fretboard(tuning: TuningPreset.dadgad.tuning), Fretboard(tuning: TuningPreset.openG.tuning)] {
            for seed in UInt64(0)..<120 {
                let history = [past("2026-09-03", nil)]
                let theme = picker(seed: seed, history: history).theme(on: fretboard, system: .caged)
                let position = try #require(theme.position(on: fretboard))
                let fitting = Progression.library(theme.key.mode)
                    .filter { fretboard.fits($0, in: theme.key, position: position) }
                guard fitting.count == 1 else { continue }
                checked += 1
                let leftOut = [past("2026-09-03", fitting[0].id)]
                #expect(picker(seed: seed, history: leftOut).theme(on: fretboard, system: .caged).progression == fitting[0])
            }
        }
        #expect(checked > 0)
    }

    @Test func aRerollChangesIt() {
        for seed in UInt64(0)..<8 {
            var theme = picker(seed: seed).theme(on: standard, system: .caged)
            for rerolls in 1..<12 {
                let next = picker(seed: seed, rerolls: rerolls).theme(on: standard, system: .caged, replacing: theme)
                #expect(next.progression != theme.progression)
                theme = next
            }
        }
    }

    @Test func aThemeWithoutOneGainsOneAndKeepsTheRest() {
        let old = Theme(key: .major(.f), position: caged(3), stringSet: .dGB)
        let new = picker().keepingKey(of: old, on: standard, system: .caged)
        #expect(new.progression != nil)
        #expect(fits(new, on: standard))
        #expect(Theme(key: new.key, position: new.position, stringSet: new.stringSet) == old)
        #expect(picker().keepingKey(of: old, on: standard, system: .caged) == new)
    }

    @Test func aFittingOneIsKept() {
        for progression in Progression.library(.major) {
            let theme = Theme(key: .major(.g), position: caged(CAGEDShape.e.number), stringSet: .dGB,
                              progression: progression)
            guard fits(theme, on: standard) else { continue }
            #expect(picker().keepingKey(of: theme, on: standard, system: .caged).progression == progression)
        }
    }

    @Test(arguments: [TuningPreset.dropD, .dadgad, .openG], [0, 3])
    func aDisqualifiedOneIsPickedAgainWithTheKeyKept(preset: TuningPreset, capo: Int) {
        let fretboard = Fretboard(tuning: preset.tuning, capo: capo)
        for seed in UInt64(0)..<25 {
            let theme = picker(seed: seed).theme(on: standard, system: .caged)
            let kept = picker(seed: seed).keepingKey(of: theme, on: fretboard, system: .caged)
            #expect(kept.key == theme.key)
            if let progression = kept.progression {
                #expect(fits(kept, on: fretboard))
                if fits(theme, on: fretboard) { #expect(progression == theme.progression) }
            }
        }
    }

    @Test func oneOfTheOtherModeIsPickedAgain() {
        let theme = Theme(key: .minor(.a), position: caged(1), stringSet: .dGB, progression: named("I–IV–V"))
        let kept = picker().keepingKey(of: theme, on: standard, system: .caged)
        #expect(kept.progression?.mode == .minor)
    }

    @Test func aSessionPlaysTheThemesProgression() {
        var setup = DrillSetup(fretboard: standard, seed: 1)
        let theme = Theme(key: .major(.g), position: caged(CAGEDShape.e.number), stringSet: .dGB,
                          progression: named("I–V–vi–IV"))
        setup.follow(theme)
        #expect(setup.options.progression == named("I–V–vi–IV"))
        #expect(DrillKind.nearestVoicing.makeDrill(setup).nothingToPromptReason == nil)
        setup.follow(Theme(key: .major(.g), position: caged(CAGEDShape.e.number), stringSet: .dGB))
        #expect(setup.options.progression == nil)
    }
}
