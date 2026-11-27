import Testing
import PracticeCore
import TheoryCore

/// The fade level each voicing's shape has reached, from clean voicings logged by the triad drills.
private func reached(_ levels: [(voicing: TriadVoicing, level: Int)]) -> FadeLevels {
    var reached = FadeLevels()
    for (voicing, level) in levels {
        let shape = FadeLevels.VoicingShape(tuning: .standard, quality: voicing.triad.quality, inversion: voicing.inversion,
                                            stringSet: voicing.stringSet)
        for number in 0..<level {
            reached.add(voicing: (0..<3).map {
                FadeLevels.VoicingNote(shape: shape, level: FadeLevel(number), hinted: false, place: $0, outcome: .answered,
                                       firstRight: true)
            })
        }
    }
    return reached
}

/// The neck's chord's markers at `time`, without the next chord's ghosted.
private func markers(_ run: inout ProgressionRun, at time: Double) -> [DrillDisplay.Marker] {
    run.tick(time)
    return run.drill.display?.markers.filter { !$0.isFaint } ?? []
}

@Suite("Progression drills fading")
struct ProgressionFadeTests {
    /// Stay in position: G [4 3 3] at level 1, the rest at 0. G sounds 4–8 s, so its notes fade over 90 % of 4 s.
    private func gAtLevelOne() -> ProgressionRun {
        let run = ProgressionRun(.stayInPosition)
        return ProgressionRun(.stayInPosition, fadeLevels: reached([(run.voicing(0, [4, 3, 3]), 1)]))
    }

    @Test func eachChordsVoicingFadesAtItsLevelOverTheChordsLength() {
        var run = gAtLevelOne()
        run.start()
        #expect(markers(&run, at: 3).map(\.opacity) == [1, 1, 1])
        #expect(run.drill.display?.progression?.timeThroughText == "1st time through · Level 1")
        let mid = markers(&run, at: 5.8)
        #expect(mid.count == 3)
        #expect(mid.filter(\.isAnswer).map(\.opacity) == [1])
        #expect(mid.filter { !$0.isAnswer }.map(\.opacity) == [0.5, 0.5])
        // D, at level 0, is shown the whole time.
        #expect(markers(&run, at: 11.4).map(\.opacity) == [1, 1, 1])
        #expect(run.drill.display?.progression?.timeThroughText == "1st time through · Level 0")
    }

    @Test func notesPlayedStaySolid() {
        var run = gAtLevelOne()
        run.start()
        run.play(run.voicing(0, [4, 3, 3]), from: 4)
        #expect(markers(&run, at: 7.4).map(\.opacity) == [1, 1, 1])
    }

    @Test func chordAttemptsRecordTheirVoicingsLevel() {
        var run = gAtLevelOne()
        run.start()
        run.tick(4 + 16 * 4 + 0.3)
        // G [4 3 3] comes up in the 1st and 4th times through; chords don't move levels.
        #expect(run.chordFacts.map(\.fadeLevel.number) == [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0])
    }

    @Test func theRunNoLongerFadesByTimesThrough() {
        var run = ProgressionRun(.stayInPosition)
        run.start()
        run.tick(4 + 16 * 5 + 0.3)
        #expect(run.chordFacts.allSatisfy { $0.fadeLevel == .first })
        #expect(markers(&run, at: 86).map(\.opacity) == [1, 1, 1])
    }

    @Test func atLevelSixOnlyTheRootIsShownAndAHintShowsAll() {
        var run = ProgressionRun(.stayInPosition, override: .last)
        run.start()
        #expect(markers(&run, at: 4.5).map(\.isAnswer) == [true])
        #expect(run.drill.display?.highlightedStrings.isEmpty == true)
        run.drill.handle(.hint(isShown: true, at: s(5)))
        #expect(run.drill.display?.markers.map(\.opacity) == [1, 1, 1])
        run.drill.handle(.hint(isShown: false, at: s(5.5)))
        run.tick(20.3)
        #expect(run.chordFacts.allSatisfy { $0.fadeLevel == .last })
    }

    @Test func theNextChordIsGhostedOnlyWhileItsVoicingIsAtLevelZero() throws {
        var shown = ProgressionRun(.stayInPosition)
        shown.start()
        shown.tick(5)
        #expect(try #require(shown.drill.display).markers.contains(where: \.isFaint))
        var faded = ProgressionRun(.stayInPosition, fadeLevels: reached([(shown.voicing(1, [2, 3, 2]), 1)]))
        faded.start()
        faded.tick(5)
        #expect(try #require(faded.drill.display).markers.contains(where: \.isFaint) == false)
    }

    @Test func resumingTakesUpWhatWasReachedMeanwhile() {
        var run = ProgressionRun(.stayInPosition)
        run.start()
        run.drill.handle(.pause(at: s(1)))
        run.drill.handle(.fadeLevels(reached([(run.voicing(0, [4, 3, 3]), 6)])))
        run.drill.handle(.resume(at: s(2)))
        // The count-in is 2–6 s, then G.
        #expect(markers(&run, at: 6.5).map(\.isAnswer) == [true])
    }
}
