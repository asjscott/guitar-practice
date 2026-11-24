import Testing
import TheoryCore

@Suite("Key and key-aware spelling")
struct KeySpellingTests {
    private func names(_ notes: [NoteName]) -> String {
        notes.map(\.description).joined(separator: " ")
    }

    @Test func bFlatInFMajor() {
        #expect(Key.major(.f).spell(PitchClass(10)).description == "B♭")
    }

    @Test func aSharpInBMajor() {
        #expect(Key.major(.b).spell(PitchClass(10)).description == "A♯")
    }

    @Test func eFlatInABlues() {
        let aBlues = Scale(.blues, tonic: .a)
        #expect(aBlues.spell(PitchClass(3)).description == "E♭")
        // Chosen tonic A, blues → A blues, still E♭.
        #expect(Scale(.blues, in: .minor(.a)).spell(PitchClass(3)).description == "E♭")
    }

    @Test func dSharpMinorIsSpelledLikeFSharpMajor() {
        let dSharpMinor = Key.minor(.dSharp)
        let fSharpMajor = Key.major(.fSharp)
        #expect(names(dSharpMinor.notes) == "D♯ E♯ F♯ G♯ A♯ B C♯")
        #expect(Set(dSharpMinor.notes) == Set(fSharpMajor.notes))
        for pitchClass in PitchClass.allCases {
            #expect(dSharpMinor.spell(pitchClass) == fSharpMajor.spell(pitchClass))
        }
        #expect(dSharpMinor.signature == 6)
    }

    @Test func bFlatMinorIsSpelledLikeDFlatMajor() {
        #expect(Set(Key.minor(.bFlat).notes) == Set(Key.major(.dFlat).notes))
        #expect(Key.minor(.bFlat).signature == -5)
    }

    @Test func sharpsWhenNoKeyApplies() {
        let spelled = PitchClass.allCases.map { Key.spell($0, in: nil).description }
        #expect(spelled == ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"])
    }

    @Test func outOfKeyNotesUseFlatsInFlatKeysAndSharpsOtherwise() {
        #expect(Key.major(.f).spell(PitchClass(1)).description == "D♭")
        #expect(Key.major(.c).spell(PitchClass(1)).description == "C♯")
        #expect(Key.major(.g).spell(PitchClass(10)).description == "A♯")
    }

    @Test func appKeysAreTheTwelveMajorKeysInPickerOrder() {
        #expect(Key.appMajorKeys.map(\.shortName)
            == ["C", "G", "D", "A", "E", "B", "F♯", "F", "B♭", "E♭", "A♭", "D♭"])
        #expect(Set(Key.appMajorKeys.map(\.tonic.pitchClass)).count == 12)
    }

    @Test func appMinorKeysAreTheRelativeMinorsSpelledFromTheirMajor() {
        #expect(Key.appMinorKeys.map(\.shortName)
            == ["Am", "Em", "Bm", "F♯m", "C♯m", "G♯m", "D♯m", "Dm", "Gm", "Cm", "Fm", "B♭m"])
        #expect(Key.minor(.dSharp).relativeMajor == .major(.fSharp))
        #expect(Key.major(.dFlat).relativeMinor == .minor(.bFlat))
    }

    @Test func pickerLabelsPerMode() {
        #expect(Key.appKeys(.major).map(\.tonic.description)
            == ["C", "G", "D", "A", "E", "B", "F♯", "F", "B♭", "E♭", "A♭", "D♭"])
        #expect(Key.appKeys(.minor).map(\.tonic.description)
            == ["A", "E", "B", "F♯", "C♯", "G♯", "D♯", "D", "G", "C", "F", "B♭"])
        #expect(Key.appKeys(.minor).allSatisfy { $0.mode == .minor })
    }

    @Test func appKeyForAPickedPitchClassAndMode() {
        #expect(Key.app(tonic: PitchClass(9), mode: .minor) == .minor(.a))
        #expect(Key.app(tonic: PitchClass(9), mode: .major) == .major(.a))
        #expect(Key.app(tonic: PitchClass(1), mode: .major) == .major(.dFlat))
        #expect(Key.app(tonic: PitchClass(1), mode: .minor) == .minor(.cSharp))
        #expect(Key.app(tonic: PitchClass(10), mode: .minor) == .minor(.bFlat))
        for mode in Key.Mode.allCases {
            #expect(PitchClass.allCases.map { Key.app(tonic: $0, mode: mode).tonic.pitchClass } == PitchClass.allCases)
        }
    }

    @Test func switchingModeKeepsThePitchClass() {
        #expect(Key.major(.dFlat).withMode(.minor) == .minor(.cSharp))
        #expect(Key.major(.eFlat).withMode(.minor) == .minor(.dSharp))
        #expect(Key.major(.aFlat).withMode(.minor) == .minor(.gSharp))
        #expect(Key.minor(.a).withMode(.major) == .major(.a))
        #expect(Key.minor(.bFlat).withMode(.major) == .major(.bFlat))
        #expect(Key.minor(.dSharp).withMode(.major) == .major(.eFlat))
        #expect(Key.major(.c).withMode(.major) == .major(.c))
    }

    @Test(arguments: [
        (NoteName.cFlat, -7, "C♭ D♭ E♭ F♭ G♭ A♭ B♭"),
        (.gFlat, -6, "G♭ A♭ B♭ C♭ D♭ E♭ F"),
        (.dFlat, -5, "D♭ E♭ F G♭ A♭ B♭ C"),
        (.aFlat, -4, "A♭ B♭ C D♭ E♭ F G"),
        (.eFlat, -3, "E♭ F G A♭ B♭ C D"),
        (.bFlat, -2, "B♭ C D E♭ F G A"),
        (.f, -1, "F G A B♭ C D E"),
        (.c, 0, "C D E F G A B"),
        (.g, 1, "G A B C D E F♯"),
        (.d, 2, "D E F♯ G A B C♯"),
        (.a, 3, "A B C♯ D E F♯ G♯"),
        (.e, 4, "E F♯ G♯ A B C♯ D♯"),
        (.b, 5, "B C♯ D♯ E F♯ G♯ A♯"),
        (.fSharp, 6, "F♯ G♯ A♯ B C♯ D♯ E♯"),
        (.cSharp, 7, "C♯ D♯ E♯ F♯ G♯ A♯ B♯"),
    ])
    func allFifteenMajorKeySignatures(tonic: NoteName, signature: Int, expected: String) {
        let key = Key.major(tonic)
        #expect(key.signature == signature)
        #expect(names(key.notes) == expected)
    }

    @Test func fifteenSignaturesFromSevenFlatsToSevenSharps() {
        #expect(Key.allMajorKeySignatures.map(\.signature) == Array(-7...7))
    }

    @Test func signatureAccidentalsInWrittenOrder() {
        #expect(names(Key.major(.e).signatureAccidentals) == "F♯ C♯ G♯ D♯")
        #expect(names(Key.major(.aFlat).signatureAccidentals) == "B♭ E♭ A♭ D♭")
        #expect(Key.major(.c).signatureAccidentals.isEmpty)
    }

    @Test func keySpellingNeverDependsOnPitchClassAlone() {
        // Pitch class 6 is G♭ in G♭ major, F♯ in D major.
        #expect(Key.major(.gFlat).spell(PitchClass(6)).description == "G♭")
        #expect(Key.major(.d).spell(PitchClass(6)).description == "F♯")
        // Pitch class 11 is C♭ in G♭ major.
        #expect(Key.major(.gFlat).spell(PitchClass(11)).description == "C♭")
    }

    @Test func names() {
        #expect(Key.major(.bFlat).description == "B♭ major")
        #expect(Key.minor(.dSharp).description == "D♯ minor")
        #expect(Key.minor(.dSharp).shortName == "D♯m")
    }
}

@Suite("A key's own scale")
struct KeyScaleTests {
    @Test func majorOrNaturalMinorOnTheTonic() {
        #expect(Key.major(.bFlat).scale == Scale(.major, tonic: .bFlat))
        #expect(Key.minor(.dSharp).scale == Scale(.naturalMinor, tonic: .dSharp))
    }
}
