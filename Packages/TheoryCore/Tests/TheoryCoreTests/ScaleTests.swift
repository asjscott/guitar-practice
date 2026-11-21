import Testing
import TheoryCore

@Suite("Scales")
struct ScaleTests {
    private func names(_ scale: Scale) -> String {
        scale.notes.map(\.description).joined(separator: " ")
    }

    @Test(arguments: [
        (Scale.Kind.major, "C D E F G A B"),
        (.naturalMinor, "C D E♭ F G A♭ B♭"),
        (.majorPentatonic, "C D E G A"),
        (.minorPentatonic, "C E♭ F G B♭"),
        (.blues, "C E♭ F G♭ G B♭"),
    ])
    func degreeFormulasFromC(kind: Scale.Kind, expected: String) {
        #expect(names(Scale(kind, tonic: .c)) == expected)
    }

    @Test func aBluesHasEFlatNotDSharp() {
        #expect(names(Scale(.blues, tonic: .a)) == "A C D E♭ E G")
    }

    // Sharp tonic (E) and flat tonic (B♭): every kind is built on the key's own tonic.
    @Test(arguments: [
        (Scale.Kind.major, "E F♯ G♯ A B C♯ D♯", "B♭ C D E♭ F G A"),
        (.naturalMinor, "E F♯ G A B C D", "B♭ C D♭ E♭ F G♭ A♭"),
        (.majorPentatonic, "E F♯ G♯ B C♯", "B♭ C D F G"),
        (.minorPentatonic, "E G A B D", "B♭ D♭ E♭ F A♭"),
    ])
    func scalesOnSharpAndFlatTonics(kind: Scale.Kind, onE: String, onBFlat: String) {
        #expect(names(Scale(kind, in: Key(tonic: .e, mode: kind.mode))) == onE)
        #expect(names(Scale(kind, in: Key(tonic: .bFlat, mode: kind.mode))) == onBFlat)
    }

    @Test func bluesOnSharpAndFlatTonics() {
        // ♭5 is spelled on the 5th degree's letter: C♯ blues has G (not F𝄪), G blues has D♭.
        #expect(names(Scale(.blues, in: .minor(.cSharp))) == "C♯ E F♯ G G♯ B")
        #expect(names(Scale(.blues, in: .minor(.g))) == "G B♭ C D♭ D F")
        #expect(names(Scale(.blues, in: .minor(.a))) == "A C D E♭ E G")
    }

    @Test func aNaturalMinorIsBuiltOnA() {
        #expect(names(Scale(.naturalMinor, in: .minor(.a))) == "A B C D E F G")
        // Picking A then natural minor: the key follows the scale's mode, the tonic stays A.
        #expect(names(Scale(.naturalMinor, in: .major(.a))) == "A B C D E F G")
        #expect(names(Scale(.major, in: .minor(.a))) == "A B C♯ D E F♯ G♯")
    }

    @Test func scalesAreBuiltOnTheKeysOwnTonic() {
        #expect(Scale(.naturalMinor, in: .minor(.a)).tonic == .a)
        #expect(Scale(.minorPentatonic, in: .minor(.dSharp)).tonic == .dSharp)
        #expect(Scale(.blues, in: .minor(.bFlat)).tonic == .bFlat)
        #expect(Scale(.major, in: .major(.dFlat)).tonic == .dFlat)
        #expect(Scale(.majorPentatonic, in: .major(.c)).tonic == .c)
    }

    @Test func aMismatchedModeKeepsThePitchClassAndUsesTheAppKeyForTheScalesMode() {
        // D♭ major + natural minor → C♯ minor (not D♭ minor, which needs B𝄫).
        #expect(Scale(.naturalMinor, in: .major(.dFlat)).tonic == .cSharp)
        #expect(Scale(.blues, in: .major(.eFlat)).tonic == .dSharp)
        #expect(Scale(.minorPentatonic, in: .major(.aFlat)).tonic == .gSharp)
        // D♯ minor + major → E♭ major.
        #expect(Scale(.major, in: .minor(.dSharp)).tonic == .eFlat)
    }

    @Test func minorScaleNotesMatchTheRelativeMajorsSpelling() {
        for key in Key.appKeys(.minor) {
            #expect(Set(Scale(.naturalMinor, in: key).notes) == Set(Scale(.major, in: key.relativeMajor).notes))
        }
    }

    @Test func scaleNotesAreSpelledOnConsecutiveLettersForSevenNoteScales() {
        for kind in [Scale.Kind.major, .naturalMinor] {
            for key in Key.appKeys(kind.mode) {
                let letters = Scale(kind, in: key).notes.map(\.letter)
                #expect(Set(letters).count == 7, "\(Scale(kind, in: key))")
                #expect(Scale(kind, in: key).notes.allSatisfy { abs($0.accidental) <= 1 })
            }
        }
    }

    @Test func containsAndDegree() {
        let aBlues = Scale(.blues, tonic: .a)
        #expect(aBlues.contains(PitchClass(3)))
        #expect(!aBlues.contains(PitchClass(1)))
        #expect(aBlues.degree(of: PitchClass(3))?.name == "♭5")
        #expect(aBlues.degree(of: PitchClass(9))?.name == "1")
        #expect(aBlues.degree(of: PitchClass(11)) == nil)
    }

    @Test func notesOutsideTheScaleFollowItsKey() {
        // C major pentatonic has no F: the key of C spells it. F major pentatonic has no B♭: F major spells it.
        #expect(Scale(.majorPentatonic, tonic: .c).spell(PitchClass(5)).description == "F")
        #expect(Scale(.majorPentatonic, tonic: .f).spell(PitchClass(10)).description == "B♭")
    }

    @Test func minorSideScales() {
        #expect(Scale.Kind.allCases.filter(\.isMinor) == [.naturalMinor, .minorPentatonic, .blues])
        #expect(Scale.Kind.allCases.map(\.mode) == [.major, .minor, .major, .minor, .minor])
    }

    @Test func sevenNoteScales() {
        #expect(Scale.Kind.allCases.filter(\.isSevenNote) == [.major, .naturalMinor])
    }

    @Test func names() {
        #expect(Scale(.major, in: .major(.c)).name == "C major")
        #expect(Scale(.naturalMinor, in: .minor(.a)).name == "A natural minor")
        #expect(Scale(.blues, in: .minor(.a)).name == "A blues")
        #expect(Scale(.blues, in: .minor(.dSharp)).name == "D♯ blues")
    }
}
