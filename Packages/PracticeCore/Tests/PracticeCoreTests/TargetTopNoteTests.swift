import Testing
import PracticeCore
import TheoryCore

/// See `ProgressionRun`. In G's E shape the top-note line of I–V–vi–IV is G4 F♯4 G4 G4 (67 66 67 67): G [4 3 3],
/// D [2 3 2], Em [4 5 3] and C [5 5 3] are the voicings with those on top.
@Suite("Target top note")
struct TargetTopNoteTests {
    @Test func eachChordAcceptsItsVoicingsWithTheLinesTopNote() {
        var run = ProgressionRun(.targetTopNote)
        run.start()
        run.tick(4 + 16 * 2 + 0.3)
        let accepted = run.chordFacts.map { $0.accepted.map { $0.locations.map(\.fret) } }
        let line = [[[4, 3, 3]], [[2, 3, 2]], [[4, 5, 3]], [[5, 5, 3]]]
        #expect(accepted == line + line)
    }

    @Test func aVoicingWithTheTopNoteIsCleanAndOneWithAnotherIsWrong() {
        var run = ProgressionRun(.targetTopNote)
        run.start()
        run.play(0, [4, 3, 3])
        // D on D-G-B, top note D: in the position, but not F♯.
        run.play(1, [4, 2, 3])
        run.tick(12.3)
        #expect(run.chordFacts.map(\.outcome) == [.clean, .wrong])
    }

    @Test func anyVoicingInThePositionWithTheTopNoteCounts() throws {
        // Every CAGED shape of G and of E minor: what each chord accepts is exactly its voicings with the line's note.
        for key in [Key.major(.g), Key.minor(.e)] {
            let fretboard = Fretboard(tuning: .standard)
            for position in fretboard.cagedPositions(of: key.scale) where position.octave == 0 {
                for progression in Progression.library(key.mode) {
                    var options = DrillOptions()
                    options.key = key
                    options.progression = progression
                    options.position = position.id
                    options.backing = BackingSettings(tempo: 60)
                    var drill = DrillKind.targetTopNote.makeDrill(DrillSetup(fretboard: fretboard, options: options,
                                                                             seed: 1))
                    drill.handle(.start(at: s(0)))
                    drill.handle(.tick(at: s(4 + 4 * Double(progression.bars) + 0.3)))
                    let line = try #require(fretboard.topNoteLine(of: progression, in: key, position: position))
                    let facts = drill.attempts.compactMap(\.chord)
                    #expect(facts.count == progression.steps.count)
                    for (index, chord) in facts.enumerated() {
                        let all = fretboard.voicings(of: chord.triad, in: position)
                        #expect(Set(chord.accepted) == Set(all.filter { fretboard.pitch(at: $0.locations[2]) == line[index] }))
                    }
                }
            }
        }
    }

    @Test func theLineIsDrawnNamedAtEveryFadeStage() throws {
        var run = ProgressionRun(.targetTopNote)
        run.start()
        for time: Double in [5, 37, 69] {
            run.tick(time)
            let progress = try #require(run.drill.display?.progression)
            #expect(progress.topNotes?.map(\.name) == ["G", "F♯", "G", "G"])
            #expect(progress.topNotes?.map(\.pitch.midi) == [67, 66, 67, 67])
        }
        #expect(run.drill.display?.progression?.fadeStage == .hidden)
        #expect(run.drill.display?.markers.isEmpty == true)
    }

    @Test func theNeckDrawsAVoicingWithTheTopNote() throws {
        var run = ProgressionRun(.targetTopNote)
        run.start()
        run.tick(8.5)
        let display = try #require(run.drill.display)
        let current = Set(display.markers.filter { !$0.isFaint }.map(\.location))
        #expect(current == Set(run.voicing(1, [2, 3, 2]).locations))
    }
}
