import Testing
import TheoryCore

@Suite("Locations on one string")
struct StringQueryTests {
    let standard = Fretboard(tuning: .standard)

    @Test func locationsOnAStringWithinAFretRange() {
        let locations = standard.locations(onString: 2, frets: 0...3)
        #expect(locations == (0...3).map { FretboardLocation(string: 2, fret: $0) })
    }

    @Test func locationsOnAStringStopAtTheCapo() {
        let capo3 = Fretboard(tuning: .standard, capo: 3)
        #expect(capo3.locations(onString: 0, frets: 0...5).map(\.fret) == [3, 4, 5])
        #expect(capo3.locations(onString: 0, frets: 0...2).isEmpty)
    }

    @Test func locationsOnAStringStopAtTheLastFret() {
        #expect(standard.locations(onString: 5, frets: 20...30).map(\.fret) == [20, 21, 22])
    }

    @Test func pitchClassOnOneStringWithinFrets() {
        // E on string 6: open and the 12th fret below fret 13; also fret 24 is off the neck.
        #expect(standard.locations(of: PitchClass(4), onString: 0, frets: 0...12).map(\.fret) == [0, 12])
        #expect(standard.locations(of: PitchClass(4), onString: 0, frets: 0...22).map(\.fret) == [0, 12])
        // F♯ on string 3 (G): fret 11 only up to 12, frets 11 and 23 (off) up to 22.
        #expect(standard.locations(of: PitchClass(6), onString: 3, frets: 0...12).map(\.fret) == [11])
    }

    @Test func pitchClassOnOneStringRespectsTheCapo() {
        let capo2 = Fretboard(tuning: .standard, capo: 2)
        #expect(capo2.locations(of: PitchClass(4), onString: 0, frets: 0...12).map(\.fret) == [12])
    }

    @Test func locationsByTheirIntervalAboveTheOpenString() {
        func frets(capo: Int = 0, string: Int = 0, within range: ClosedRange<Int>) -> [Int] {
            Fretboard(tuning: .standard, capo: capo)
                .locations(onString: string, frets: range, aboveOpen: Interval(1)...Interval(12)).map(\.fret)
        }
        #expect(frets(within: 0...22) == Array(1...12))
        #expect(frets(within: 0...3) == [1, 2, 3])
        // With a capo the open string sounds at the capo.
        #expect(frets(capo: 5, string: 5, within: 0...22) == Array(6...17))
        // Capo 12: the neck ends 10 frets up.
        #expect(frets(capo: 12, within: 0...22) == Array(13...22))
        #expect(frets(capo: 12, within: 0...12) == [])
    }

    @Test(arguments: [TuningPreset.dropD, .dadgad, .openG], [0, 3, 12])
    func intervalsAboveTheOpenStringInOtherTunings(preset: TuningPreset, capo: Int) {
        let board = Fretboard(tuning: preset.tuning, capo: capo)
        let intervals = Interval(1)...Interval(12)
        for string in board.strings {
            let found = board.locations(onString: string, frets: 0...22, aboveOpen: intervals)
            #expect(found.allSatisfy { $0.string == string && (capo...22).contains($0.fret) })
            #expect(found.allSatisfy { intervals.contains(board.pitch(at: $0) - board.soundingOpenPitch(ofString: string)) })
            // A fret per semitone, in order and none missing.
            #expect(found.map(\.fret) == Array(capo + 1...min(capo + 12, 22)))
            #expect(board.locations(onString: string, frets: 0...12, aboveOpen: intervals) == found.filter { $0.fret <= 12 })
        }
    }

    @Test func exactPitchOnOneStringWithinFrets() {
        // E3 (52) on string 6 is fret 12; E2 (40) is fret 0.
        #expect(standard.location(of: Pitch(52), onString: 0, frets: 0...12) == FretboardLocation(string: 0, fret: 12))
        #expect(standard.location(of: Pitch(40), onString: 0, frets: 0...12) == FretboardLocation(string: 0, fret: 0))
        // E3 on string 6 is outside frets 0–5; E4 is not on string 6 below fret 13.
        #expect(standard.location(of: Pitch(52), onString: 0, frets: 0...5) == nil)
        #expect(standard.location(of: Pitch(64), onString: 0, frets: 0...12) == nil)
        // Below the capo is unplayable.
        let capo3 = Fretboard(tuning: .standard, capo: 3)
        #expect(capo3.location(of: Pitch(40), onString: 0, frets: 0...12) == nil)
    }

    @Test func invariantsInOtherTunings() {
        for tuning in [TuningPreset.dropD, .dadgad, .openG].map(\.tuning) {
            for capo in [0, 3] {
                let board = Fretboard(tuning: tuning, capo: capo)
                for string in board.strings {
                    for pc in PitchClass.allCases {
                        for location in board.locations(of: pc, onString: string, frets: 0...12) {
                            #expect(location.string == string)
                            #expect((capo...12).contains(location.fret))
                            #expect(board.pitch(at: location).pitchClass == pc)
                            #expect(board.location(of: board.pitch(at: location), onString: string, frets: 0...12) == location)
                        }
                    }
                }
            }
        }
    }
}

@Suite("Natural notes")
struct NaturalNoteTests {
    @Test func naturalsAreTheWhiteKeys() {
        #expect(PitchClass.allCases.filter(\.isNatural).map(\.value) == [0, 2, 4, 5, 7, 9, 11])
    }
}

@Suite("String labels")
struct StringLabelTests {
    @Test func standardLabels() {
        #expect(Tuning.standard.stringLabel(ofString: 3) == "string 3 (G)")
        #expect(Tuning.standard.stringLabel(ofString: 0) == "string 6 (E)")
        #expect(Tuning.standard.stringLabel(ofString: 5) == "string 1 (E)")
    }

    @Test func dadgadLabels() {
        let dadgad = TuningPreset.dadgad.tuning
        #expect(dadgad.stringLabel(ofString: 5) == "string 1 (D)")
        #expect(dadgad.stringLabel(ofString: 2) == "string 4 (D)")
        #expect(dadgad.stringLabel(ofString: 0) == "string 6 (D)")
    }

    @Test func openNoteNamesFollowTheTuningsSpelling() {
        #expect(TuningPreset.openD.tuning.openNoteName(ofString: 3).description == "F♯")
        #expect(TuningPreset.eFlatStandard.tuning.openNoteName(ofString: 0).description == "E♭")
    }

    @Test func drillLabelsUseSharpsEvenInAFlatNamedTuning() {
        // Drill prompts have no key, so they're all sharps: "D♯ on string 6 (D♯)" in E♭ standard.
        let eFlat = TuningPreset.eFlatStandard.tuning
        #expect(eFlat.stringLabel(ofString: 0) == "string 6 (D♯)")
        #expect(eFlat.stringLabel(ofString: 3) == "string 3 (F♯)")
        // The tuner and Settings keep the preset's flats.
        #expect(eFlat.openNoteName(ofString: 0).description == "E♭")
        #expect(eFlat.openPitchNames[0] == "E♭2")
    }
}
