import Testing
import TheoryCore
import PracticeCore

private let standard = Fretboard(tuning: .standard)
private let dropDCapo12 = Fretboard(tuning: TuningPreset.dropD.tuning, capo: 12)
/// No string set has a voicing of any chord.
private let wild = Fretboard(tuning: Tuning([24, 48, 72, 24, 48, 72].map(Pitch.init)), capo: 12)

private func picker(seed: UInt64 = 1, rerolls: Int = 0, history: [PastTheme] = []) -> ThemePicker {
    ThemePicker(day: "2026-09-30", seed: seed, rerolls: rerolls, history: history)
}

private func caged(_ number: Int) -> Position.ID { Position.ID(system: .caged, number: number) }

private func past(_ day: String, _ set: StringSet?) -> PastTheme {
    PastTheme(day: day, theme: Theme(key: .major(.c), position: caged(1), stringSet: set))
}

/// The sets of many seeds.
private func sets(_ history: [PastTheme] = []) -> Set<StringSet?> {
    Set((UInt64(0)..<60).map { picker(seed: $0, history: history).theme(on: standard, system: .caged).stringSet })
}

@Suite("Theme's string set")
struct ThemeStringSetTests {
    @Test(arguments: [TuningPreset.standard, .dropD, .dadgad, .openG])
    func everySetComesUp(preset: TuningPreset) {
        let picked = (UInt64(0)..<40).map {
            picker(seed: $0).theme(on: Fretboard(tuning: preset.tuning), system: .caged).stringSet
        }
        #expect(Set(picked) == [.eAD, .aDG, .dGB, .gBE])
    }

    @Test(arguments: [TuningPreset.standard, .dropD, .dadgad, .openG], [0, 12])
    func noSetHasMoreOfTheKeysChords(preset: TuningPreset, capo: Int) throws {
        let fretboard = Fretboard(tuning: preset.tuning, capo: capo)
        for seed in UInt64(0)..<20 {
            let theme = picker(seed: seed).theme(on: fretboard, system: .caged)
            let count = fretboard.chordCount(of: theme.key, on: try #require(theme.stringSet))
            for set in StringSet.allCases { #expect(fretboard.chordCount(of: theme.key, on: set) <= count) }
        }
    }

    @Test func theLastPractisedDaysIsLeftOut() {
        #expect(sets([past("2026-09-03", .dGB), past("2026-09-01", .eAD)]) == [.eAD, .aDG, .gBE])
        #expect(sets([past("2026-09-03", .dGB), past("2026-09-03", .gBE)]) == [.eAD, .aDG])
        #expect(sets([past("2026-09-03", nil), past("2026-09-01", .eAD)]).count == 4)
        #expect(sets([past("2026-09-30", .eAD)]).count == 4)
    }

    @Test func unlessItIsTheOnlyChoice() {
        // Only E-A-D has strings close enough.
        let one = Fretboard(tuning: Tuning([40, 45, 50, 24, 72, 24].map(Pitch.init)))
        let theme = picker(history: [past("2026-09-03", .eAD)]).theme(on: one, system: .caged)
        #expect(theme.stringSet == .eAD)
    }

    @Test func aRerollChangesIt() {
        for fretboard in [standard, dropDCapo12] {
            for seed in UInt64(0)..<5 {
                var theme = picker(seed: seed).theme(on: fretboard, system: .caged)
                for rerolls in 1..<24 {
                    let next = picker(seed: seed, rerolls: rerolls).theme(on: fretboard, system: .caged, replacing: theme)
                    #expect(next.stringSet != theme.stringSet)
                    theme = next
                }
            }
        }
    }

    @Test func aThemeWithoutOneGetsOneAndKeepsTheRest() {
        let old = Theme(key: .major(.f), position: caged(3))
        let new = picker().keepingKey(of: old, on: standard, system: .caged)
        #expect(new.stringSet != nil)
        #expect(Theme(key: new.key, position: new.position) == old)
        #expect(picker().keepingKey(of: old, on: standard, system: .caged) == new)
    }

    @Test func aDisqualifiedOneIsPickedAgainWithTheKeyKept() {
        // On E-A-D, Drop D with the capo at 12 has no G major but all of F major's chords.
        for seed in UInt64(0)..<10 {
            let theme = Theme(key: .major(.c), position: caged(3), stringSet: .eAD)
            let kept = picker(seed: seed).keepingKey(of: theme, on: dropDCapo12, system: .caged)
            #expect(kept.key == .major(.c))
            #expect(kept.stringSet != .eAD && kept.stringSet != nil)
            let still = Theme(key: .major(.f), position: caged(3), stringSet: .eAD)
            #expect(picker(seed: seed).keepingKey(of: still, on: dropDCapo12, system: .caged).stringSet == .eAD)
        }
    }

    @Test func noneWhereNoChordHasAVoicing() {
        #expect(picker().theme(on: wild, system: .caged).stringSet == nil)
        let theme = Theme(key: .major(.c), position: caged(3), stringSet: .eAD)
        #expect(picker().keepingKey(of: theme, on: wild, system: .caged).stringSet == nil)
    }
}
