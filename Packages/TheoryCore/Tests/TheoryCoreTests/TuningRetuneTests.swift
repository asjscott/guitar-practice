import Testing
import TheoryCore

@Suite("Retuning a string")
struct TuningRetuneTests {
    @Test func eachStringIsLimitedToMIDI24To72() {
        #expect(Tuning.openPitchRange == Pitch(24)...Pitch(72))
    }

    @Test func steppingAStringChangesOnlyThatString() {
        let dropped = Tuning.standard.retuning(string: 0, by: Interval(-2))
        #expect(dropped.openPitches.map(\.midi) == [38, 45, 50, 55, 59, 64])
        #expect(dropped.preset == .dropD)
    }

    @Test func steppingStopsAtTheRangeEnds() {
        let low = Tuning([24, 72].map(Pitch.init))
        #expect(!low.canRetune(string: 0, by: Interval(-1)))
        #expect(low.canRetune(string: 0, by: Interval(1)))
        #expect(!low.canRetune(string: 1, by: Interval(1)))
        #expect(low.canRetune(string: 1, by: Interval(-1)))
        #expect(low.retuning(string: 0, by: Interval(-1)) == low)
        #expect(low.retuning(string: 1, by: Interval(1)) == low)
    }

    @Test func steppingClampsALargeStepToTheRange() {
        let tuning = Tuning([30].map(Pitch.init))
        #expect(tuning.retuning(string: 0, by: Interval(-12)).openPitches == [Pitch(24)])
    }

    @Test func steppingMayMakeATuningReEntrant() {
        // String 3 (G3) tuned down below string 4 (D3): allowed.
        let reEntrant = Tuning.standard.retuning(string: 3, by: Interval(-7))
        #expect(reEntrant.openPitches.map(\.midi) == [40, 45, 50, 48, 59, 64])
        #expect(reEntrant.isWithinOpenPitchRange)
    }

    @Test func aTuningKnowsWhetherEveryStringIsInRange() {
        #expect(Tuning.standard.isWithinOpenPitchRange)
        #expect(Tuning([24, 72].map(Pitch.init)).isWithinOpenPitchRange)
        #expect(!Tuning([23, 40].map(Pitch.init)).isWithinOpenPitchRange)
        #expect(!Tuning([40, 73].map(Pitch.init)).isWithinOpenPitchRange)
    }
}
