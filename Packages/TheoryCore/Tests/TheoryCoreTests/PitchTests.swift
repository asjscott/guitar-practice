import Testing
import TheoryCore

@Suite("Pitch, pitch class and interval")
struct PitchTests {
    @Test func middleCIsMIDI60InOctave4() {
        let middleC = Pitch(60)
        #expect(middleC.midi == 60)
        #expect(middleC.pitchClass == PitchClass(0))
        #expect(middleC.octave == 4)
    }

    @Test(arguments: [
        (40, 4, 2),   // low E string: E2
        (45, 9, 2),   // A2
        (59, 11, 3),  // B3
        (64, 4, 4),   // high E: E4
        (24, 0, 1),   // C1
        (72, 0, 5),   // C5
        (11, 11, -1), // B-1
    ])
    func pitchClassAndOctave(midi: Int, pitchClass: Int, octave: Int) {
        #expect(Pitch(midi).pitchClass == PitchClass(pitchClass))
        #expect(Pitch(midi).octave == octave)
    }

    @Test func pitchClassWrapsIntoZeroToEleven() {
        #expect(PitchClass(12) == PitchClass(0))
        #expect(PitchClass(14).value == 2)
        #expect(PitchClass(-1).value == 11)
        #expect(PitchClass(-13).value == 11)
    }

    @Test func twelvePitchClassesFromC() {
        #expect(PitchClass.allCases.map(\.value) == Array(0...11))
    }

    @Test func pitchesAndIntervalsAdd() {
        #expect(Pitch(40) + Interval(5) == Pitch(45))
        #expect(Pitch(45) - Interval(5) == Pitch(40))
        #expect(Pitch(64) - Pitch(40) == Interval(24))
    }

    @Test func pitchClassesAddIntervalsAndWrap() {
        #expect(PitchClass(9) + Interval(4) == PitchClass(1))   // A + major 3rd = C♯
        #expect(PitchClass(2) - Interval(3) == PitchClass(11))  // D − minor 3rd = B
    }

    @Test func intervalFromOnePitchClassUpToAnother() {
        #expect(PitchClass(9).interval(upTo: PitchClass(0)) == Interval(3))  // A up to C
        #expect(PitchClass(0).interval(upTo: PitchClass(9)) == Interval(9))
        #expect(PitchClass(4).interval(upTo: PitchClass(4)) == Interval(0))
    }

    @Test func intervalsAreSemitones() {
        #expect(Interval(7).semitones == 7)
        #expect(Interval.octave == Interval(12))
        #expect(Interval(3) + Interval(4) == Interval(7))
    }

    @Test func pitchesOrderByHeight() {
        #expect(Pitch(40) < Pitch(41))
        #expect([Pitch(64), Pitch(40), Pitch(50)].sorted() == [Pitch(40), Pitch(50), Pitch(64)])
    }

    @Test func sharpNamesWhenNoKeyApplies() {
        #expect(PitchClass.allCases.map(\.sharpName)
            == ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"])
    }
}

@Suite("Relative heights")
struct RelativeHeightTests {
    @Test func fromTheLowestToTheHighest() {
        #expect([45, 47, 53, 49].map { Pitch($0) }.relativeHeights == [0, 0.25, 1, 0.5])
    }

    @Test func allAlikeOrNone() {
        #expect([Pitch(45), Pitch(45)].relativeHeights == [0, 0])
        #expect([Pitch]().relativeHeights == [])
    }
}
