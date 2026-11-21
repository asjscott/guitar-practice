import Testing
import TheoryCore

@Suite("Tuning presets")
struct TuningPresetTests {
    @Test(arguments: [
        (TuningPreset.standard, [40, 45, 50, 55, 59, 64]),      // E2 A2 D3 G3 B3 E4
        (TuningPreset.dropD, [38, 45, 50, 55, 59, 64]),         // D2 A2 D3 G3 B3 E4
        (TuningPreset.dadgad, [38, 45, 50, 55, 57, 62]),        // D2 A2 D3 G3 A3 D4
        (TuningPreset.openG, [38, 43, 50, 55, 59, 62]),         // D2 G2 D3 G3 B3 D4
        (TuningPreset.openD, [38, 45, 50, 54, 57, 62]),         // D2 A2 D3 F♯3 A3 D4
        (TuningPreset.eFlatStandard, [39, 44, 49, 54, 58, 63]), // E♭2 A♭2 D♭3 G♭3 B♭3 E♭4
    ])
    func presetHasTheRightOpenPitchesFromString6(preset: TuningPreset, midi: [Int]) {
        #expect(preset.tuning.openPitches == midi.map(Pitch.init))
    }

    @Test func presetsAreListedInPickerOrderWithNames() {
        #expect(TuningPreset.allCases.map(\.name)
            == ["Standard", "Drop D", "DADGAD", "Open G", "Open D", "E♭ standard"])
    }

    @Test func standardPresetIsTheStandardTuning() {
        #expect(TuningPreset.standard.tuning == .standard)
    }

    @Test func aTuningKnowsWhichPresetItMatches() {
        #expect(Tuning.standard.preset == .standard)
        #expect(TuningPreset.dadgad.tuning.preset == .dadgad)
        #expect(Tuning([38, 45, 50, 55, 59, 63].map(Pitch.init)).preset == nil)
    }
}
