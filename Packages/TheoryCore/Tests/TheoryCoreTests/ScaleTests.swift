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

    // Sharp key (E major, relative minor C♯) and flat key (B♭ major, relative minor G).
    @Test(arguments: [
        (Scale.Kind.major, "E F♯ G♯ A B C♯ D♯", "B♭ C D E♭ F G A"),
        (.naturalMinor, "C♯ D♯ E F♯ G♯ A B", "G A B♭ C D E♭ F"),
        (.majorPentatonic, "E F♯ G♯ B C♯", "B♭ C D F G"),
        (.minorPentatonic, "C♯ E F♯ G♯ B", "G B♭ C D F"),
    ])
    func scalesInSharpAndFlatKeys(kind: Scale.Kind, inE: String, inBFlat: String) {
        #expect(names(Scale(kind, in: .major(.e))) == inE)
        #expect(names(Scale(kind, in: .major(.bFlat))) == inBFlat)
    }

    @Test func bluesInSharpAndFlatKeys() {
        // ♭5 is spelled on the 5th degree's letter: C♯ blues has G (not F𝄪), G blues has D♭.
        #expect(names(Scale(.blues, in: .major(.e))) == "C♯ E F♯ G G♯ B")
        #expect(names(Scale(.blues, in: .major(.bFlat))) == "G B♭ C D♭ D F")
    }

    @Test func minorScalesUseTheRelativeMinorOfTheChosenKey() {
        #expect(Scale(.naturalMinor, in: .major(.c)).tonic == .a)
        #expect(Scale(.minorPentatonic, in: .major(.fSharp)).tonic == .dSharp)
        #expect(Scale(.blues, in: .major(.dFlat)).tonic == .bFlat)
        #expect(Scale(.major, in: .major(.dFlat)).tonic == .dFlat)
        #expect(Scale(.majorPentatonic, in: .minor(.a)).tonic == .c)
    }

    @Test func minorScaleNotesMatchTheRelativeMajorsSpelling() {
        for key in Key.appMajorKeys {
            #expect(Set(Scale(.naturalMinor, in: key).notes) == Set(Scale(.major, in: key).notes))
        }
    }

    @Test func scaleNotesAreSpelledOnConsecutiveLettersForSevenNoteScales() {
        for key in Key.appMajorKeys {
            for kind in [Scale.Kind.major, .naturalMinor] {
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

    @Test func sevenNoteScales() {
        #expect(Scale.Kind.allCases.filter(\.isSevenNote) == [.major, .naturalMinor])
    }

    @Test func names() {
        #expect(Scale(.major, in: .major(.c)).name == "C major")
        #expect(Scale(.naturalMinor, in: .major(.c)).name == "A natural minor")
        #expect(Scale(.blues, in: .major(.fSharp)).name == "D♯ blues")
    }
}
