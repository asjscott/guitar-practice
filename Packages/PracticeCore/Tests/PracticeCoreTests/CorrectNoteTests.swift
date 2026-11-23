import Testing
import TheoryCore
import PracticeCore

/// Seconds as a `Duration`, for readable scripts.
func s(_ seconds: Double) -> Duration { .milliseconds(Int((seconds * 1000).rounded())) }

/// E on string 6 first: "In order (check)" on string 6 alone starts at fret 0.
func lowEDrill(frets: ClosedRange<Int> = 0...12) -> NotePlayItDrill {
    var options = NotePlayItOptions()
    options.notes = .all
    options.frets = frets
    options.strings = [0]
    options.order = .inOrder
    var drill = NotePlayItDrill(fretboard: Fretboard(tuning: .standard), options: options, seed: 1)
    drill.handle(.start(at: s(0)))
    return drill
}

@Suite("Correct notes")
struct CorrectNoteTests {
    @Test func promptIsEOnString6() {
        let drill = lowEDrill()
        #expect(drill.prompt?.pitchClass == PitchClass(4))
        #expect(drill.prompt?.string == 0)
        #expect(drill.phase == .waiting)
    }

    @Test(arguments: [(40, 0), (52, 12)])
    func eOnString6AcceptsFret0AndFret12(midi: Int, fret: Int) {
        var drill = lowEDrill()
        drill.handle(.played(Pitch(midi), onset: s(0.8), at: s(0.9)))
        let location = FretboardLocation(string: 0, fret: fret)
        #expect(drill.phase == .correct(location))
        #expect(drill.attempts.count == 1)
        #expect(drill.attempts[0].firstRight)
        #expect(drill.attempts[0].responseTime == s(0.8))
        #expect(drill.attempts[0].location == location)
        #expect(drill.attempts[0].wrongNotes.isEmpty)
    }

    @Test func samePitchOnAnotherStringCounts() {
        // E3 is fret 12 on string 6 and fret 2 on string 4: the app can't tell them apart.
        var drill = lowEDrill()
        drill.handle(.played(Pitch(52), onset: s(1), at: s(1.1)))
        #expect(drill.phase == .correct(FretboardLocation(string: 0, fret: 12)))
        #expect(drill.attempts.first?.firstRight == true)
    }

    @Test func rightPitchClassOutsideTheFretRangeIsWrong() {
        // E3 is fret 12 on string 6, outside frets 0–5.
        var drill = lowEDrill(frets: 0...5)
        drill.handle(.played(Pitch(52), onset: s(1), at: s(1.1)))
        #expect(drill.phase == .wrong(PitchClass(4)))
        #expect(drill.attempts.isEmpty)
    }

    @Test func nextPromptAbout400msAfterARightNote() {
        var drill = lowEDrill()
        drill.handle(.played(Pitch(40), onset: s(1), at: s(1.1)))
        drill.handle(.tick(at: s(1.45)))
        #expect(drill.phase == .correct(FretboardLocation(string: 0, fret: 0)))
        drill.handle(.tick(at: s(1.5)))
        #expect(drill.phase == .waiting)
        // In order on string 6: fret 1 is F.
        #expect(drill.prompt?.pitchClass == PitchClass(5))
        #expect(drill.prompt?.target == FretboardLocation(string: 0, fret: 1))
    }
}
