import Testing
import TheoryCore
import PracticeCore

/// A run on string 6 alone, all notes; one fret in range gives one prompt.
private func fretNameIt(_ tuning: Tuning = .standard, capo: Int = 0, frets: ClosedRange<Int>, key: Key? = nil) -> any Drill {
    var options = DrillOptions()
    options.notes = .all
    options.frets = frets
    options.strings = [0]
    var drill = DrillKind.fretNameIt.makeDrill(DrillSetup(fretboard: Fretboard(tuning: tuning, capo: capo), options: options,
                                                          key: key, seed: 1))
    drill.handle(.start(at: s(0)))
    return drill
}

@Suite("Fret → name it")
struct FretNameItTests {
    let fret6 = FretboardLocation(string: 0, fret: 6)

    @Test func theRightNameIsTimedToSubmitting() {
        var drill = fretNameIt(frets: 6...6)
        #expect(drill.prompt?.target == fret6)
        drill.handle(.typed(.aSharp, at: s(1.25)))
        #expect(drill.phase == .correct(fret6))
        #expect(drill.attempts == [Attempt(prompt: NotePrompt(name: .aSharp, string: 0, target: fret6), outcome: .answered,
                                           responseTime: s(1.25), location: fret6)])
        #expect(drill.attempts[0].firstRight)
    }

    @Test(arguments: [(6, NoteName.bFlat), (0, NoteName(.f, -1)), (1, NoteName(.e, 1)), (7, .cFlat), (8, NoteName(.b, 1))])
    func anyEnharmonicNameIsRight(fret: Int, name: NoteName) {
        var drill = fretNameIt(frets: fret...fret)
        drill.handle(.typed(name, at: s(1)))
        #expect(drill.phase == .correct(FretboardLocation(string: 0, fret: fret)))
    }

    @Test func aWrongNameKeepsThePromptAndIsLoggedAsTyped() throws {
        var drill = fretNameIt(frets: 6...6)
        drill.handle(.typed(.gFlat, at: s(1)))
        let display = try #require(drill.display)
        #expect(display.feedback == "Not G♭")
        #expect(display.result == .wrong)
        #expect(display.headline == "?")
        #expect(display.acceptsTypedName)
        #expect(drill.prompt?.target == fret6)
        drill.handle(.typed(.bFlat, at: s(2)))
        #expect(drill.attempts[0].rawWrongAnswers == [.named(.gFlat)])
        #expect(drill.attempts[0].responseTime == s(2))
        #expect(!drill.attempts[0].firstRight)
    }

    @Test func waitingHidesTheNameAndShowsThePlace() throws {
        let display = try #require(fretNameIt(frets: 6...6).display)
        #expect(display.headline == "?")
        #expect(display.subline == "string 6 (E) · fret 6")
        #expect(display.feedback == "Type its name, then Return")
        #expect(display.acceptsTypedName)
        #expect(display.markers == [.init(location: fret6, label: "?", isAnswer: false)])
    }

    @Test func aRightAnswerShowsTheNameInTheKey() throws {
        var drill = fretNameIt(frets: 6...6, key: .major(.bFlat))
        drill.handle(.typed(.aSharp, at: s(0.82)))
        let display = try #require(drill.display)
        #expect(display.headline == "B♭")
        #expect(display.feedback == "B♭ · 0.82 s")
        #expect(display.result == .right)
        #expect(!display.acceptsTypedName)
        #expect(display.markers == [.init(location: fret6, label: "B♭", isAnswer: true)])
    }

    @Test func tenSecondsRevealsTheName() throws {
        var drill = fretNameIt(frets: 6...6)
        #expect(drill.timeLimit == s(10))
        drill.handle(.typed(.a, at: s(9)))
        drill.handle(.typed(.aSharp, at: s(10)))
        let display = try #require(drill.display)
        #expect(display.headline == "A♯")
        #expect(display.feedback == "Time's up — it's A♯")
        #expect(display.result == .timedOut)
        #expect(display.markers == [.init(location: fret6, label: "A♯", isAnswer: false)])
        #expect(drill.attempts.map(\.outcome) == [.timedOut])
        #expect(drill.attempts[0].rawWrongAnswers == [.named(.a)])
    }

    @Test func playedNotesAreIgnored() {
        var drill = fretNameIt(frets: 6...6)
        drill.handle(.played(Pitch(46), onset: s(1), at: s(1.1)))
        #expect(drill.phase == .waiting)
    }

    @Test func dropDNamesWhatTheRetunedStringGives() {
        var drill = fretNameIt(TuningPreset.dropD.tuning, frets: 3...3)
        drill.handle(.typed(.g, at: s(1)))
        #expect(drill.phase == .wrong(PitchClass(7)))
        drill.handle(.typed(.f, at: s(2)))
        #expect(drill.phase == .correct(FretboardLocation(string: 0, fret: 3)))
    }

    @Test func aCapoCountsFretsFromTheNut() {
        // Capo 12 on string 6: only fret 12, E, is left of frets 0–12.
        var drill = fretNameIt(capo: 12, frets: 0...12)
        #expect(drill.prompt?.target == FretboardLocation(string: 0, fret: 12))
        drill.handle(.typed(.e, at: s(1)))
        #expect(drill.phase == .correct(FretboardLocation(string: 0, fret: 12)))
        var capo2 = fretNameIt(capo: 2, frets: 3...3)
        capo2.handle(.typed(.g, at: s(1)))
        #expect(capo2.phase == .correct(FretboardLocation(string: 0, fret: 3)))
    }

    @Test func everyLocationInRangeIsAskedForAndNoneTwiceRunning() {
        var options = DrillOptions()
        options.frets = 0...5
        var drill = DrillKind.fretNameIt.makeDrill(DrillSetup(fretboard: Fretboard(tuning: TuningPreset.dadgad.tuning, capo: 2),
                                                              options: options, seed: 3))
        drill.handle(.start(at: s(0)))
        var asked: [FretboardLocation] = []
        for _ in 0..<400 {
            asked.append(drill.prompt!.target!)
            drill.handle(.skip(at: s(0)))
        }
        #expect(Set(asked) == Set(drill.setup.candidateLocations))
        #expect(asked.allSatisfy { (2...5).contains($0.fret) })
        #expect(zip(asked, asked.dropFirst()).allSatisfy { $0 != $1 })
    }
}

@Suite("Typing a note name")
struct NoteNameEntryTests {
    /// What is shown after typing `keys`.
    private func typed(_ keys: String) -> String {
        let drill = fretNameIt(frets: 6...6)
        var entry = NoteNameEntry()
        for key in keys { _ = entry.press(.character(key), for: drill, at: s(1)) }
        return entry.text
    }

    @Test(arguments: [("", ""), ("g", "G"), ("f#", "F♯"), ("b", "B"), ("bb", "B♭"), ("ab", "A♭"), ("AB", "A♭"),
                      ("#", ""), ("cd", "D"), ("c#e", "E"), ("c#b", "B"), ("c##", "C♯"), ("c#bb", "B♭")])
    func lettersAndAccidentals(keys: String, text: String) {
        #expect(typed(keys) == text)
    }

    @Test func deleteTakesTheAccidentalThenTheLetter() {
        let drill = fretNameIt(frets: 6...6)
        var entry = NoteNameEntry()
        for key in "bb" { _ = entry.press(.character(key), for: drill, at: s(1)) }
        _ = entry.press(.delete, for: drill, at: s(1))
        #expect(entry.text == "B")
        _ = entry.press(.delete, for: drill, at: s(1))
        _ = entry.press(.delete, for: drill, at: s(1))
        #expect(entry.text == "")
    }

    @Test func returnSubmitsAndClears() {
        let drill = fretNameIt(frets: 6...6)
        var entry = NoteNameEntry()
        #expect(entry.press(.submit, for: drill, at: s(1)) == .taken(nil))
        _ = entry.press(.character("b"), for: drill, at: s(1))
        #expect(entry.press(.submit, for: drill, at: s(2)) == .taken(.typed(.b, at: s(2))))
        #expect(entry.text == "")
    }

    @Test func aNewPromptClearsWhatWasTyped() {
        var drill = fretNameIt(frets: 5...6)
        var entry = NoteNameEntry()
        entry.follow(drill)
        _ = entry.press(.character("g"), for: drill, at: s(1))
        drill.handle(.tick(at: s(2)))
        entry.follow(drill)
        #expect(entry.text == "G")
        drill.handle(.skip(at: s(3)))
        entry.follow(drill)
        #expect(entry.text == "")
    }

    @Test func aRevealClearsWhatWasTyped() {
        var drill = fretNameIt(frets: 5...6)
        var entry = NoteNameEntry()
        entry.follow(drill)
        _ = entry.press(.character("g"), for: drill, at: s(9))
        drill.handle(.tick(at: s(10.2)))
        entry.follow(drill)
        #expect(entry.text == "")
    }

    @Test func noteKeysAreTakenThroughoutARunButOnlyTypedWhileAPromptWaits() {
        var drill = fretNameIt(frets: 5...6)
        var entry = NoteNameEntry()
        drill.handle(.typed(drill.prompt!.name, at: s(1)))
        #expect(entry.press(.character("d"), for: drill, at: s(1)) == .taken(nil))
        #expect(entry.press(.submit, for: drill, at: s(1)) == .taken(nil))
        #expect(entry.text == "")
        drill.handle(.pause(at: s(1)))
        #expect(entry.press(.character("d"), for: drill, at: s(1)) == .taken(nil))
        #expect(entry.text == "")
        // Paused, Return is left for whatever is on screen.
        #expect(entry.press(.submit, for: drill, at: s(1)) == .notTaken)
        drill.handle(.stop(at: s(1)))
        #expect(entry.press(.character("d"), for: drill, at: s(1)) == .notTaken)
    }

    @Test(arguments: ["s", "p", "r", " ", "+", "h", "1"])
    func otherKeysAreNotTaken(key: String) {
        var entry = NoteNameEntry()
        #expect(entry.press(.character(Character(key)), for: fretNameIt(frets: 6...6), at: s(1)) == .notTaken)
    }

    @Test func nothingIsTakenInADrillAnsweredOnTheGuitar() {
        var entry = NoteNameEntry()
        #expect(entry.press(.character("d"), for: lowEDrill(), at: s(1)) == .notTaken)
    }
}
