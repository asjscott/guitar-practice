import Testing
import TheoryCore

/// G major's E shape in standard tuning, frets 2–5. The top notes its voicings have:
/// G 67 only (G B D on G-B-E); D 54 57 62 66; Em 52 64 67; C 52 64 67.
@Suite("The top-note line, standard tuning")
struct StandardTopNoteLineTests {
    let fretboard = Fretboard(tuning: .standard)
    let g = Key.major(.g)

    func shape(_ shape: CAGEDShape, of key: Key) throws -> Position {
        try #require(fretboard.cagedPositions(of: key.scale).first { $0.cagedShape == shape && $0.octave == 0 })
    }

    @Test func startsOnTheRootAsHighAsThePositionHoldsThenTheNearestChordTone() throws {
        let line = fretboard.topNoteLine(of: Progression.named("I–V–vi–IV")!, in: g, position: try shape(.e, of: g))
        // G4, then F♯4 (a semitone down), then G4 and G4 again.
        #expect(line?.map(\.midi) == [67, 66, 67, 67])
    }

    @Test func aCommonToneStaysPut() throws {
        // G, C (G on top again), D (F♯, a semitone below G).
        let line = fretboard.topNoteLine(of: Progression.named("I–IV–V")!, in: g, position: try shape(.e, of: g))
        #expect(line?.map(\.midi) == [67, 67, 66])
    }

    @Test func everyKeyAndShapeKeepsTheRules() {
        for key in Key.appMajorKeys + Key.appMinorKeys {
            for position in fretboard.cagedPositions(of: key.scale) {
                for progression in Progression.library(key.mode) {
                    guard let line = fretboard.topNoteLine(of: progression, in: key, position: position) else {
                        Issue.record("\(progression.id) in \(key) has no line in the \(position.name)")
                        continue
                    }
                    TopNoteLineInvariants.check(line, of: progression, in: key, position: position, on: fretboard)
                }
            }
        }
    }
}

enum TopNoteLineInvariants {
    /// Each top note is the top of some voicing of its chord in the position; the first is the chord's root, as high
    /// as one goes, when any voicing has it on top; each next is a smallest step, the lower when two are as small.
    static func check(_ line: [Pitch], of progression: Progression, in key: Key, position: Position,
                      on fretboard: Fretboard) {
        let chords = progression.chords(in: key)
        #expect(line.count == chords.count)
        let tops = chords.map { chord in
            Set(fretboard.voicings(of: chord, in: position).map(fretboard.topPitch))
        }
        for (top, available) in zip(line, tops) { #expect(available.contains(top)) }
        guard let first = line.first else { return }
        let roots = tops[0].filter { $0.pitchClass == chords[0].root.pitchClass }
        #expect(first == (roots.max() ?? tops[0].max()), "\(progression.id) in \(key), \(position.name)")
        for index in line.indices.dropFirst() {
            let step = abs((line[index] - line[index - 1]).semitones)
            let steps = tops[index].map { abs(($0 - line[index - 1]).semitones) }
            #expect(step == steps.min(), "\(progression.id) in \(key), \(position.name), chord \(index)")
            let tied = tops[index].filter { abs(($0 - line[index - 1]).semitones) == step }
            #expect(line[index] == tied.min())
        }
    }
}

@Suite("The top-note line, other tunings and a capo")
struct TopNoteLineInvariantTests {
    static let fretboards: [Fretboard] = [
        Fretboard(tuning: TuningPreset.dropD.tuning), Fretboard(tuning: TuningPreset.dadgad.tuning),
        Fretboard(tuning: TuningPreset.openG.tuning), Fretboard(tuning: .standard, capo: 3),
        Fretboard(tuning: TuningPreset.dropD.tuning, capo: 5),
    ]

    @Test(arguments: fretboards)
    func everyStepIsTheSmallestAvailable(fretboard: Fretboard) {
        for key in Key.appMajorKeys + Key.appMinorKeys {
            for position in fretboard.cagedPositions(of: key.scale) {
                for progression in Progression.library(key.mode) {
                    let line = fretboard.topNoteLine(of: progression, in: key, position: position)
                    #expect((line != nil) == fretboard.fits(progression, in: key, position: position))
                    if let line {
                        TopNoteLineInvariants.check(line, of: progression, in: key, position: position, on: fretboard)
                    }
                }
            }
        }
    }
}
