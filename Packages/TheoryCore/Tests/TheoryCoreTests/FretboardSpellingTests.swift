import Testing
import TheoryCore

@Suite("Fretboard: spelled names and whole-neck scales")
struct FretboardSpellingTests {
    private let standard = Fretboard(tuning: .standard)
    private let dropD = Fretboard(tuning: Tuning([38, 45, 50, 55, 59, 64].map(Pitch.init)))
    private let dadgad = Fretboard(tuning: Tuning([38, 45, 50, 55, 57, 62].map(Pitch.init)))

    @Test func nameAtALocationFollowsTheKey() {
        // String 6 (index 0) fret 6 is B♭/A♯.
        let location = FretboardLocation(string: 0, fret: 6)
        #expect(standard.name(at: location, in: Key.major(.f)).description == "B♭")
        #expect(standard.name(at: location, in: Key.major(.b)).description == "A♯")
        #expect(standard.name(at: location, in: nil as Key?).description == "A♯")
    }

    @Test func nameAtALocationFollowsTheScale() {
        // String 5 (index 1) fret 6 is E♭ in A blues.
        let location = FretboardLocation(string: 1, fret: 6)
        #expect(standard.name(at: location, in: Scale(.blues, tonic: .a)).description == "E♭")
    }

    @Test func cMajorPentatonicOnString6() {
        let frets = standard.locations(of: Scale(.majorPentatonic, tonic: .c))
            .filter { $0.string == 0 }.map(\.fret)
        // E2 string: E(0) G(3) A(5) C(8) D(10) E(12) G(15) A(17) C(20) D(22).
        #expect(frets == [0, 3, 5, 8, 10, 12, 15, 17, 20, 22])
    }

    @Test(arguments: Scale.Kind.allCases)
    func wholeNeckScaleHoldsOnlyScaleNotesInAnyTuning(kind: Scale.Kind) {
        for fretboard in [standard, dropD, dadgad] {
            let scale = Scale(kind, in: .major(.eFlat))
            let locations = fretboard.locations(of: scale)
            #expect(locations.allSatisfy { scale.contains(fretboard.pitch(at: $0).pitchClass) })
            #expect(locations.allSatisfy(fretboard.isPlayable))
            let expected = fretboard.allLocations.filter { scale.contains(fretboard.pitch(at: $0).pitchClass) }
            #expect(locations == expected)
        }
    }

    @Test func stringNamesFollowTheKey() {
        let eFlatStandard = Fretboard(tuning: Tuning([39, 44, 49, 54, 58, 63].map(Pitch.init)))
        #expect(eFlatStandard.stringNames(in: Key.major(.eFlat)).map(\.description)
            == ["E♭", "A♭", "D♭", "G♭", "B♭", "E♭"])
        #expect(standard.stringNames(in: nil as Key?).map(\.description) == ["E", "A", "D", "G", "B", "E"])
        #expect(dropD.stringNames(in: Key.major(.d)).map(\.description) == ["D", "A", "D", "G", "B", "E"])
    }
}
