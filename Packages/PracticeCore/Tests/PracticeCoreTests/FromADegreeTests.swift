import Testing
import TheoryCore
import PracticeCore

/// A minor pentatonic at frets 5–8 in standard, unless changed.
private func setup(_ tuning: Tuning = TuningPreset.standard.tuning, _ kind: Scale.Kind = .minorPentatonic,
                   key: Key = .minor(.a), number: Int = CAGEDShape.g.number, capo: Int = 0, seed: UInt64 = 1) -> DrillSetup {
    var options = DrillOptions()
    options.key = key
    options.scaleKind = kind
    options.position = Position.ID(system: .caged, number: number)
    return DrillSetup(fretboard: Fretboard(tuning: tuning, capo: capo), options: options, seed: seed)
}

private func started(_ setup: DrillSetup) -> any Drill {
    var drill = DrillKind.fromADegree.makeDrill(setup)
    drill.handle(.start(at: s(0)))
    return drill
}

/// What each of the first passes is headed and starts on, skipping from one to the next.
private func passes(_ count: Int, of setup: DrillSetup) -> [(headline: String, midi: Int?)] {
    var drill = started(setup)
    return (0..<count).map { index in
        defer { drill.handle(.skip(at: s(Double(index + 1)))) }
        return (drill.display?.headline ?? "", drill.prompt?.target.map { setup.fretboard.pitch(at: $0).midi })
    }
}

private func headlines(_ count: Int, of setup: DrillSetup) -> [String] { passes(count, of: setup).map(\.headline) }

@Suite("From a degree")
struct FromADegreeTests {
    @Test func itIsAScalesDrill() {
        #expect(DrillKind.all.filter { $0.module == .scales } == [.upAndDown, .fromADegree])
        #expect(DrillKind.fromADegree.id == "fromADegree")
        #expect(DrillKind.fromADegree.title == "From a degree")
        #expect(DrillKind.fromADegree.hasPasses)
        #expect(DrillKind.fromADegree.repeatTitle == "Restart")
    }

    @Test func theSublineNamesTheScale() {
        #expect(started(setup()).display?.subline == "A minor pentatonic · G shape")
    }

    @Test func everyDegreeButTheRootOnItsLowestLocation() {
        let starts = passes(4, of: setup()).sorted { ($0.midi ?? 0) < ($1.midi ?? 0) }
        #expect(starts.map(\.headline) == ["Start on ♭3 (C)", "Start on 4 (D)", "Start on 5 (E)", "Start on ♭7 (G)"])
        #expect(starts.map(\.midi) == [48, 50, 52, 55])
    }

    @Test(arguments: [
        (Scale.Kind.major, Key.major(.a), ["2 (B)", "3 (C♯)", "4 (D)", "5 (E)", "6 (F♯)", "7 (G♯)"]),
        (.naturalMinor, .minor(.a), ["2 (B)", "♭3 (C)", "4 (D)", "5 (E)", "♭6 (F)", "♭7 (G)"]),
        (.majorPentatonic, .major(.a), ["2 (B)", "3 (C♯)", "5 (E)", "6 (F♯)"]),
        (.blues, .minor(.a), ["♭3 (C)", "4 (D)", "♭5 (E♭)", "5 (E)", "♭7 (G)"]),
        (.blues, .major(.dFlat), ["♭3 (E)", "4 (F♯)", "♭5 (G)", "5 (G♯)", "♭7 (B)"]),
    ])
    func theScalesOwnDegreesSpelledInIt(kind: Scale.Kind, key: Key, degrees: [String]) {
        let asked = headlines(degrees.count, of: setup(TuningPreset.standard.tuning, kind, key: key))
        #expect(Set(asked) == Set(degrees.map { "Start on \($0)" }))
    }

    @Test func eachOnceBeforeAnyRepeatsAndNeverTwiceInARow() {
        var orders = Set<[String]>()
        for seed in UInt64(1)...20 {
            let asked = headlines(12, of: setup(seed: seed))
            for start in [0, 4, 8] { #expect(Set(asked[start..<start + 4]).count == 4) }
            #expect(zip(asked, asked.dropFirst()).allSatisfy { $0 != $1 })
            orders.insert(Array(asked.prefix(4)))
        }
        #expect(orders.count > 5)
    }

    @Test func thePassStartsAndEndsOnTheDegreeAndLogsIt() throws {
        var drill = started(setup())
        let headline = try #require(drill.display?.headline)
        var played: [Pitch] = []
        for index in 0..<23 {
            let target = try #require(drill.prompt?.target)
            played.append(drill.fretboard.pitch(at: target))
            drill.handle(.played(played[index], onset: s(Double(4 + index)), at: s(Double(4 + index) + 0.13)))
        }
        #expect(drill.display?.feedback == "Clean pass")
        #expect(played.first == played.last)
        let degrees = drill.attempts.compactMap { attempt in
            if case .pass(let facts) = attempt.facts { facts.startDegree } else { nil }
        }
        #expect(degrees.count == 23)
        let degree = try #require(degrees.first)
        #expect(Set(degrees).count == 1)
        #expect(headline == "Start on \(degree.name) (\(drill.attempts[0].prompt.noteName))")
    }

    @Test func restartAndResumeKeepTheDegree() {
        for seed in UInt64(1)...5 {
            var drill = started(setup(seed: seed))
            let headline = drill.display?.headline
            drill.handle(.repeat(at: s(1)))
            #expect(drill.display?.headline == headline)
            drill.handle(.pause(at: s(2)))
            drill.handle(.resume(at: s(3)))
            #expect(drill.display?.headline == headline)
            drill.handle(.skip(at: s(4)))
            #expect(drill.display?.headline != headline)
        }
    }

    /// Only strings 6 and 5 of the tuning, since positions on six strings have every degree. Two notes on each of them
    /// is four of the five degrees.
    @Test(arguments: [(TuningPreset.standard, Key.minor(.a)), (.dadgad, .minor(.d))])
    func aDegreeThePositionLacksIsNotAsked(preset: TuningPreset, key: Key) throws {
        let setup = setup(Tuning(Array(preset.tuning.openPitches.prefix(2))), key: key)
        let position = try #require(setup.position)
        let there = Set(position.locations.map { setup.fretboard.pitch(at: $0).pitchClass })
        let names = setup.scale.notes.filter { there.contains($0.pitchClass) && $0 != setup.scale.tonic }.map(\.description)
        #expect(names.count == 3)
        let asked = headlines(6, of: setup)
        #expect(Set(asked).count == 3)
        for name in names { #expect(asked.filter { $0.hasSuffix("(\(name))") }.count == 2) }
    }

    @Test(arguments: [TuningPreset.standard, .dropD, .dadgad, .openG], [0, 2])
    func inAnyTuningAndWithACapo(preset: TuningPreset, capo: Int) throws {
        for kind in Scale.Kind.allCases {
            for number in 1...5 {
                let setup = setup(preset.tuning, kind, number: number, capo: capo)
                let position = try #require(setup.position)
                let count = kind.degrees.count - 1
                let starts = passes(count, of: setup)
                #expect(Set(starts.map(\.headline)).count == count)
                let pitches = position.locations.map { setup.fretboard.pitch(at: $0).midi }
                for start in starts {
                    let midi = try #require(start.midi)
                    #expect(start.headline.hasSuffix("(\(setup.scale.spell(Pitch(midi).pitchClass)))"))
                    #expect(!pitches.contains { $0 < midi && (midi - $0) % 12 == 0 })
                }
            }
        }
    }

    @Test func aPositionThatDoesntFitTheNeckSaysSo() {
        let reasons = (1...5).compactMap {
            DrillKind.fromADegree.makeDrill(setup(number: $0, capo: 12)).nothingToPromptReason
        }
        #expect(!reasons.isEmpty)
    }
}
