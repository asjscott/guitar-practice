import Testing
import TheoryCore
import PracticeCore

/// Runs a drill by answering every prompt right away, and returns the prompts it showed.
func promptsShown(by drill: inout NotePlayItDrill, count: Int) -> [NotePrompt] {
    var shown: [NotePrompt] = []
    var now = s(0)
    drill.handle(.start(at: now))
    while shown.count < count, let prompt = drill.prompt {
        shown.append(prompt)
        // Play the right note at the first correct location, then wait for the next prompt.
        let location = drill.correctLocations[0]
        now += s(0.5)
        drill.handle(.played(drill.fretboard.pitch(at: location), onset: now, at: now))
        now += NotePlayItDrill.correctPause
        drill.handle(.tick(at: now))
    }
    return shown
}

func drill(_ tuning: Tuning = .standard, capo: Int = 0, seed: UInt64 = 42,
           configure: (inout NotePlayItOptions) -> Void = { _ in }) -> NotePlayItDrill {
    var options = NotePlayItOptions()
    configure(&options)
    return NotePlayItDrill(fretboard: Fretboard(tuning: tuning, capo: capo), options: options, seed: seed)
}

@Suite("Random prompts")
struct RandomPromptTests {
    @Test func fixedSeedGivesTheSameRunAndNoImmediateRepeats() {
        var first = drill { $0.notes = .all }
        var second = drill { $0.notes = .all }
        let a = promptsShown(by: &first, count: 200)
        let b = promptsShown(by: &second, count: 200)
        #expect(a.count == 200)
        #expect(a == b)
        for (previous, next) in zip(a, a.dropFirst()) {
            #expect(previous != next)
        }
        // A different seed gives a different run.
        var other = drill(seed: 7) { $0.notes = .all }
        #expect(promptsShown(by: &other, count: 200) != a)
    }

    @Test func noImmediateRepeatsWithOnlyTwoPrompts() {
        // String 6, frets 0–1, naturals: E and F only, so they must alternate.
        var twoPrompts = drill { $0.strings = [0]; $0.frets = 0...1 }
        let shown = promptsShown(by: &twoPrompts, count: 20)
        #expect(Set(shown.map(\.pitchClass)) == [PitchClass(4), PitchClass(5)])
        for (previous, next) in zip(shown, shown.dropFirst()) {
            #expect(previous != next)
        }
    }

    @Test func randomPromptsHaveNoTarget() {
        var random = drill()
        #expect(promptsShown(by: &random, count: 20).allSatisfy { $0.target == nil })
    }

    @Test func naturalsOnlyByDefault() {
        var naturals = drill()
        let shown = promptsShown(by: &naturals, count: 300)
        #expect(shown.allSatisfy { $0.pitchClass.isNatural })
        #expect(Set(shown.map(\.pitchClass)).count == 7)
    }

    @Test func allNotesCoversEveryPitchClass() {
        var all = drill { $0.notes = .all }
        #expect(Set(promptsShown(by: &all, count: 300).map(\.pitchClass)).count == 12)
    }

    @Test func excludedStringsAreNeverPrompted() {
        var twoStrings = drill { $0.strings = [1, 4] }
        let shown = promptsShown(by: &twoStrings, count: 200)
        #expect(Set(shown.map(\.string)) == [1, 4])
    }

    @Test func fretRangeLimitsTheNotes() {
        // String 1 (E4), frets 0–3, all notes: E F F♯ G only.
        var lowFrets = drill { $0.strings = [5]; $0.frets = 0...3; $0.notes = .all }
        let shown = promptsShown(by: &lowFrets, count: 100)
        #expect(Set(shown.map(\.pitchClass)) == Set([4, 5, 6, 7].map(PitchClass.init)))
    }

    @Test func noPromptsBelowTheCapo() {
        // Capo 5 on string 6, frets 0–7: A A♯ B (frets 5–7), never E F F♯ G G♯ (frets 0–4).
        var capo = drill(capo: 5) { $0.strings = [0]; $0.frets = 0...7; $0.notes = .all }
        let shown = promptsShown(by: &capo, count: 100)
        #expect(Set(shown.map(\.pitchClass)) == Set([9, 10, 11].map(PitchClass.init)))
    }

    @Test func invariantsInOtherTuningsAndWithACapo() {
        for tuning in [TuningPreset.dropD, .dadgad, .openG].map(\.tuning) {
            for capo in [0, 3] {
                var run = drill(tuning, capo: capo) { $0.frets = 0...12 }
                let fretboard = run.fretboard
                let shown = promptsShown(by: &run, count: 100)
                #expect(shown.count == 100)
                for prompt in shown {
                    #expect(prompt.pitchClass.isNatural)
                    let answers = fretboard.locations(of: prompt.pitchClass, onString: prompt.string, frets: 0...12)
                    #expect(!answers.isEmpty)
                    #expect(answers.allSatisfy { $0.fret >= capo })
                }
            }
        }
    }

    @Test func noCandidatesMeansNoRun() {
        // Capo 12, frets 0–5: nothing playable.
        var empty = drill(capo: 12) { $0.frets = 0...5 }
        empty.handle(.start(at: s(0)))
        #expect(empty.phase == .idle)
        #expect(empty.prompt == nil)
    }
}

@Suite("In order (check)")
struct InOrderTests {
    @Test func visitsEveryLocationInRangeExactlyOnceInOrder() {
        var check = drill { $0.order = .inOrder; $0.notes = .all; $0.frets = 0...12 }
        let shown = promptsShown(by: &check, count: 1000)
        #expect(shown.count == 6 * 13)
        var expected: [FretboardLocation] = []
        for string in 0..<6 {
            for fret in 0...12 { expected.append(FretboardLocation(string: string, fret: fret)) }
        }
        #expect(shown.map(\.target) == expected)
        // The runs ends after the last location.
        #expect(check.phase == .idle)
        #expect(check.attempts.count == 78)
    }

    @Test func checkPromptsNameTheNoteAtTheirLocation() {
        var check = drill { $0.order = .inOrder; $0.notes = .all; $0.strings = [3]; $0.frets = 0...2 }
        let shown = promptsShown(by: &check, count: 10)
        #expect(shown.map(\.noteName) == ["G", "G♯", "A"])
        #expect(shown.allSatisfy { $0.string == 3 })
    }

    @Test func checkFollowsTheStringsFretsAndCapoButIgnoresTheNotesFilter() {
        // Default Notes filter is naturals; a check run still walks every location in range.
        var check = drill(capo: 2) { $0.order = .inOrder; $0.strings = [0, 5]; $0.frets = 0...5 }
        let shown = promptsShown(by: &check, count: 100)
        // String 6 frets 2–5 (F♯ G G♯ A), then string 1 (same).
        var expected: [FretboardLocation] = []
        for string in [0, 5] {
            for fret in 2...5 { expected.append(FretboardLocation(string: string, fret: fret)) }
        }
        #expect(shown.compactMap(\.target) == expected)
        #expect(shown.map(\.noteName) == ["F♯", "G", "G♯", "A", "F♯", "G", "G♯", "A"])
    }
}

@Suite("Prompt text")
struct PromptTextTests {
    @Test func spelledWithSharpsAndNamedByStringNumberAndOpenNote() {
        let prompt = NotePrompt(pitchClass: PitchClass(6), string: 3)
        #expect(prompt.text(in: .standard) == "F♯ on string 3 (G)")
    }

    @Test func dadgadLabels() {
        let dadgad = TuningPreset.dadgad.tuning
        #expect(NotePrompt(pitchClass: PitchClass(2), string: 5).stringLabel(in: dadgad) == "string 1 (D)")
        #expect(NotePrompt(pitchClass: PitchClass(2), string: 2).stringLabel(in: dadgad) == "string 4 (D)")
        #expect(NotePrompt(pitchClass: PitchClass(2), string: 0).stringLabel(in: dadgad) == "string 6 (D)")
    }

    @Test func labelsIgnoreTheCapo() {
        let capo2 = drill(capo: 2)
        #expect(NotePrompt(pitchClass: PitchClass(9), string: 3).text(in: capo2.fretboard.tuning) == "A on string 3 (G)")
    }
}
