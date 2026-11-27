import Testing
import TheoryCore
import PracticeCore

private let standard = Fretboard(tuning: .standard)
private let cShape = Position.ID(system: .caged, number: CAGEDShape.c.number)

/// A Scale circle from E major's C shape (frets 4–7) unless changed, started at 0.
private func circle(on fretboard: Fretboard = standard, _ change: (inout DrillSetup) -> Void = { _ in }) -> any Drill {
    var setup = DrillSetup(fretboard: fretboard, seed: 1)
    setup.options.key = .major(.e)
    setup.options.position = cShape
    change(&setup)
    var drill = DrillKind.scaleCircle.makeDrill(setup)
    drill.handle(.start(at: s(0)))
    return drill
}

/// Plays the prompted pitch `every` after each prompt's timer starts until the pass ends; returns its locations.
@discardableResult
private func finishPass(_ drill: inout any Drill, every interval: Double = 1) -> [FretboardLocation] {
    var played: [FretboardLocation] = []
    let pass = drill.prompt?.sweep
    while drill.isRunning, drill.prompt?.sweep == pass, let target = drill.prompt?.target, let start = drill.promptStart,
          played.count < 100 {
        played.append(target)
        drill.handle(.played(drill.fretboard.pitch(at: target), onset: start + s(interval), at: start + s(interval)))
        drill.handle(.tick(at: start + s(interval + 0.1)))
    }
    return played
}

private func play(_ drill: inout any Drill, at time: Double) {
    guard let target = drill.prompt?.target else { return }
    drill.handle(.played(drill.fretboard.pitch(at: target), onset: s(time), at: s(time)))
}

private func passFacts(_ attempt: Attempt) -> PassFacts? {
    if case .pass(let facts) = attempt.facts { facts } else { nil }
}

private func theme() throws -> Position {
    try #require(standard.cagedPositions(of: Scale(.major, tonic: .e)).first { $0.id == cShape })
}

@Suite("Scale circle: passes")
struct ScaleCirclePassTests {
    @Test func isAScaleDrillInThePickerWithAnIdThatNeverChanges() {
        #expect(DrillKind.all.contains(.scaleCircle))
        #expect(DrillKind.scaleCircle.id == "scaleCircle")
        #expect(DrillKind.scaleCircle.module == .scales)
        #expect(DrillKind.scaleCircle.goesRoundTheCircle)
        #expect(DrillKind.scaleCircle.fades)
        #expect(!DrillKind.scaleCircle.hasPasses)
    }

    @Test func upThroughTheChosenPositionThenTheNextKeyDownInTheNearest() throws {
        var drill = circle()
        let positions = standard.scaleCirclePositions(from: try theme(), going: .up)
        #expect(finishPass(&drill) == standard.passOrder(of: positions[0], going: .up))
        #expect(drill.display?.circle?.key == .major(.b))
        #expect(finishPass(&drill) == standard.passOrder(of: positions[1], going: .down))
        #expect(finishPass(&drill) == standard.passOrder(of: positions[2], going: .up))
    }

    @Test func twelvePassesRoundTheCircleThenTheRunEnds() {
        var drill = circle()
        var keys: [String] = []
        for _ in 0..<12 {
            keys.append(drill.display?.circle?.key.shortName ?? "–")
            finishPass(&drill)
        }
        #expect(keys == ["E", "B", "F♯", "D♭", "A♭", "E♭", "B♭", "F", "C", "G", "D", "A"])
        #expect(drill.display?.circle?.result?.isClean == true)
        drill.handle(.tick(at: s(10_000)))
        #expect(!drill.isRunning)
    }

    @Test func theTitleNamesTheKeyPositionAndDirectionAndTheNextOne() {
        var drill = circle()
        #expect(drill.display?.headline == "E major")
        #expect(drill.display?.subline == "major · C shape · up ↑")
        #expect(drill.display?.circle?.placeText == "E · 1 of 12")
        #expect(drill.display?.circle?.nextDetail == "G shape · down")
        finishPass(&drill)
        #expect(drill.display?.headline == "B major")
        #expect(drill.display?.subline == "major · G shape · down ↓")
    }

    @Test func aThemeStartsItFromItsKeyAndPosition() {
        var drill = circle {
            $0.options.key = .major(.c)
            $0.follow(Theme(key: .minor(.a), position: Position.ID(system: .caged, number: CAGEDShape.e.number)))
        }
        #expect(drill.display?.headline == "A natural minor")
        #expect(drill.display?.subline == "natural minor · E shape · up ↑")
    }

    @Test func aThemeAtTheNutIsPlayedTwelveFretsUp() throws {
        let drill = circle {
            $0.options.key = .major(.g)
            $0.options.position = Position.ID(system: .caged, number: CAGEDShape.e.number)
        }
        let target = try #require(drill.prompt?.target)
        #expect(target.fret >= 12)
    }
}

@Suite("Scale circle: time, wrong notes and the log")
struct ScaleCircleAnswerTests {
    @Test func aNoteNeverTimesOutAndThereAreNoClicks() {
        var drill = circle()
        #expect(drill.timeRemaining(at: s(1)) == nil)
        drill.handle(.tick(at: s(600)))
        #expect(drill.attempts.isEmpty)
        #expect(drill.takeClicks().isEmpty)
    }

    @Test func timeRunsOnFromNoteToNoteAndIntoTheNextKey() {
        var drill = circle()
        finishPass(&drill, every: 2)
        let notes = drill.attempts.count
        #expect(drill.display?.circle?.time(at: drill.promptStart ?? .zero) == s(2) * notes)
        #expect(drill.promptStart == s(2) * notes)
    }

    @Test func wrongNotesAreCountedAndASkipLeavesTheCircleNotClean() {
        var drill = circle()
        drill.handle(.played(Pitch(30), onset: s(1), at: s(1)))
        #expect(drill.display?.circle?.wrongNotes == 1)
        #expect(drill.display?.result == .wrong)
        drill.handle(.skip(at: s(2)))
        for _ in 0..<12 { finishPass(&drill) }
        let result = drill.display?.circle?.result ?? CircleResult(attempts: drill.attempts)
        #expect(result?.isComplete == true)
        #expect(result?.isClean == false)
        #expect(result?.wrongNotes == 1)
    }

    @Test func passAttemptsCarryTheirDirectionAndCircleWithoutATempo() throws {
        var drill = circle()
        let first = finishPass(&drill)
        finishPass(&drill)
        let attempts = drill.attempts
        let up = try #require(passFacts(attempts[0]))
        #expect(up.direction == .up)
        #expect(up.tempo == nil)
        #expect(up.signature == nil)
        #expect(up.scale == Scale(.major, tonic: .e))
        #expect(up.position == cShape)
        #expect(up.fadeLevel == .first)
        #expect(attempts[0].group == AttemptGroup(number: 0, size: first.count, place: 0, circle: 0))
        let down = try #require(passFacts(attempts[first.count]))
        #expect(down.direction == .down)
        #expect(down.scale == Scale(.major, tonic: .b))
        #expect(attempts[first.count].group?.number == 1)
        #expect(attempts[first.count].group?.place == 0)
        #expect(attempts[first.count].group?.circle == 0)
    }
}

@Suite("Scale circle: fade")
struct ScaleCircleFadeTests {
    private func subject(_ position: Position.ID) -> FadeLevels.Subject {
        FadeLevels.Subject(tuning: standard.tuning, scaleKind: .major, position: position)
    }

    /// Level 1 of E major's C shape, from the log: clean passes of it move it up whatever the key.
    private func level1() -> FadeLevels {
        var levels = FadeLevels()
        let notes = (0..<5).map {
            FadeLevels.Note(subject: subject(cShape), level: .first, hinted: false, size: 5, place: $0,
                            outcome: .answered, firstRight: true)
        }
        levels.add(notes)
        return levels
    }

    @Test func aNewPassIsShownWholeWithItsFirstNoteRinged() throws {
        let drill = circle()
        let markers = try #require(drill.display?.markers)
        let position = try theme()
        #expect(Set(markers.map(\.location)) == Set(position.locations))
        #expect(markers.allSatisfy { $0.opacity == 1 })
        #expect(markers.filter(\.isLastPlayed).map(\.location) == [standard.passOrder(of: position, going: .up)[0]])
        #expect(markers.filter(\.isAnswer).allSatisfy { standard.pitch(at: $0.location).pitchClass == NoteName.e.pitchClass })
    }

    /// At level 1 a pass of n notes fades by 90 % of n seconds; the roots and the notes played stay.
    @Test func atItsLevelEachPassFadesByItsOwnExpectedTime() throws {
        var drill = circle { $0.fadeLevels = level1() }
        let order = standard.passOrder(of: try theme(), going: .up)
        let fadeTime = 0.9 * Double(order.count)
        play(&drill, at: 1)
        drill.handle(.tick(at: s(fadeTime / 2)))
        let markers = try #require(drill.display?.markers)
        let first = try #require(markers.first { $0.location == order[0] })
        #expect(first.opacity == 1)
        #expect(first.isLastPlayed)
        let faded = markers.filter { !$0.isAnswer && $0.location != order[0] }
        #expect(!faded.isEmpty)
        #expect(faded.allSatisfy { abs($0.opacity - 0.5) < 0.01 })
        #expect(markers.filter(\.isAnswer).allSatisfy { $0.opacity == 1 })
        drill.handle(.tick(at: s(fadeTime + 0.1)))
        #expect(drill.display?.markers.allSatisfy { $0.isAnswer || $0.location == order[0] } == true)
        #expect(drill.attempts.compactMap(passFacts).first?.fadeLevel == FadeLevel(1))
    }

    @Test func theNextKeyIsShownWholeAgainAtItsOwnLevel() throws {
        var drill = circle { $0.fadeLevels = level1() }
        finishPass(&drill, every: 2)
        let markers = try #require(drill.display?.markers)
        #expect(markers.allSatisfy { $0.opacity == 1 })
        // B major's G shape hasn't been played: level 0 never fades.
        drill.handle(.tick(at: (drill.promptStart ?? .zero) + s(60)))
        #expect(drill.display?.markers.allSatisfy { $0.opacity == 1 } == true)
    }

    @Test func aCleanPassMovesItsPositionUpAndHShowsItAll() throws {
        var drill = circle()
        drill.handle(.hint(isShown: true, at: s(0.5)))
        drill.handle(.hint(isShown: false, at: s(0.6)))
        finishPass(&drill)
        #expect(drill.fadeLevels?.level(of: subject(cShape)) == .first)
        #expect(drill.attempts.compactMap(passFacts).first?.hinted == true)
        for _ in 0..<11 { finishPass(&drill) }
        let shapes = standard.scaleCirclePositions(from: try theme(), going: .up).dropFirst()
        #expect(shapes.contains { (drill.fadeLevels?.level(of: subject($0.id)) ?? .first) > .first })
    }

    @Test func theFadePickerOverridesTheLevel() throws {
        var drill = circle { $0.options.pass.fadeLevel = .last }
        let first = standard.passOrder(of: try theme(), going: .up)[0]
        let markers = try #require(drill.display?.markers)
        // The roots, and the ringed first note to start from.
        #expect(markers.allSatisfy { $0.isAnswer || $0.location == first })
        #expect(markers.count > 1)
        play(&drill, at: 1)
        #expect(drill.attempts.compactMap(passFacts).first?.fadeLevel == .last)
    }
}
