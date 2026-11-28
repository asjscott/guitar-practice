import Testing
import TheoryCore

@Suite("Scale circle positions in standard tuning")
struct ScaleCirclePositionsStandardTests {
    let fretboard = Fretboard(tuning: .standard)

    private func position(_ shape: CAGEDShape, of scale: Scale, octave: Int = 0) throws -> Position {
        try #require(fretboard.cagedPositions(of: scale).first { $0.cagedShape == shape && $0.octave == octave })
    }

    /// The probe's walk (#64): E major from the C shape at frets 4–7 stays about there.
    @Test func eMajorFromTheCShape() throws {
        let theme = try position(.c, of: Scale(.major, tonic: .e))
        #expect(theme.frets == 4...7)
        let circle = fretboard.scaleCirclePositions(from: theme, going: .up)
        #expect(circle.map(\.scale.key) == Key.major(.e).circleOfFifths)
        #expect(circle.first == theme)
        #expect(circle[1].scale == Scale(.major, tonic: .b))
        #expect(circle[1].cagedShape == .g)
        #expect(circle[1].frets == 3...7)
        #expect(circle[2].scale == Scale(.major, tonic: .fSharp))
        #expect(circle[2].cagedShape == .d)
        #expect(circle[2].frets == 3...7)
        #expect(circle[11].scale == Scale(.major, tonic: .a))
        #expect(circle[11].cagedShape == .e)
        #expect(circle[11].frets == 4...7)
    }

    /// B's root closest to E major's top note (G♯ at string 1 fret 4) going up: B at string 1 fret 7 (B4), in the G
    /// shape. Going down from E's bottom (G♯ at string 6 fret 4): B at string 6 fret 7 (B2), held by the G shape too.
    @Test func theNextRootIsClosestToWhereThePassEnded() throws {
        let theme = try position(.c, of: Scale(.major, tonic: .e))
        let up = fretboard.scaleCirclePositions(from: theme, going: .up)
        #expect(up[1].locations.contains(FretboardLocation(string: 5, fret: 7)))
        let down = fretboard.scaleCirclePositions(from: theme, going: .down)
        #expect(down[1].locations.contains(FretboardLocation(string: 0, fret: 7)))
    }

    /// The A shape of G major is at frets 0–3 (it touches the nut): the whole circle goes up 12, from its octave-up copy.
    @Test func aThemeAtTheNutMovesUpTwelve() throws {
        let theme = try position(.e, of: Scale(.major, tonic: .g))
        #expect(theme.frets.lowerBound <= 2)
        let circle = fretboard.scaleCirclePositions(from: theme, going: .up)
        let moved = try position(.e, of: Scale(.major, tonic: .g), octave: 1)
        #expect(circle.first == moved)
        #expect(circle.count == 12)
        #expect(circle.allSatisfy { $0.frets.lowerBound >= moved.frets.lowerBound - 2 })
    }

    /// With frets 2–5 from a capo at 0, but frets 3… from a capo at 1, the rule counts from the capo.
    @Test func touchingIsCountedFromTheCapo() throws {
        let scale = Scale(.major, tonic: .a)
        let theme = try #require(fretboard.cagedPositions(of: scale).first { $0.frets.lowerBound == 4 })
        let capo2 = Fretboard(tuning: .standard, capo: 2)
        let capoTheme = try #require(capo2.cagedPositions(of: scale).first { $0.id == theme.id })
        #expect(capoTheme.frets == theme.frets)
        #expect(fretboard.scaleCirclePositions(from: theme, going: .up).first == theme)
        #expect(capo2.scaleCirclePositions(from: capoTheme, going: .up).first?.frets.lowerBound == 16)
    }

    /// Where its octave-up copy is off the neck, the theme stays where it is.
    @Test func unlessThatLeavesTheNeck() throws {
        let capo11 = Fretboard(tuning: .standard, capo: 11)
        let scale = Scale(.major, tonic: .c)
        let theme = try #require(capo11.cagedPositions(of: scale).first)
        #expect(theme.frets.lowerBound <= 13)
        #expect(!capo11.cagedPositions(of: scale).contains { $0.id.number == theme.number && $0.octave == theme.octave + 1 })
        #expect(capo11.scaleCirclePositions(from: theme, going: .up).first == theme)
    }

    @Test func aThreeNotesPerStringThemeStaysInPatterns() throws {
        let theme = try #require(fretboard.threeNPSPositions(of: Scale(.naturalMinor, tonic: .a)).first { $0.frets.lowerBound >= 5 })
        let circle = fretboard.scaleCirclePositions(from: theme, going: .down)
        #expect(circle.count == 12)
        #expect(circle.allSatisfy { $0.system == .threeNotesPerString && $0.scale.kind == .naturalMinor })
        #expect(circle.map(\.scale.key) == Key.minor(.a).circleOfFifths)
    }
}

@Suite("Scale circle positions in any tuning")
struct ScaleCirclePositionsInvariantTests {
    /// The probe's setups (#64).
    static let setups: [(TuningPreset, Int)] = [(.standard, 0), (.dropD, 0), (.dadgad, 0), (.openG, 0), (.standard, 5)]

    /// Every key's scale (the session's), every position: twelve distinct keys in circle order, each holding its root
    /// inside the range, each within the range's frets give or take its own width.
    @Test(arguments: setups, [Key.Mode.major, .minor])
    func everyCircleCompletesNearTheTheme(setup: (TuningPreset, Int), mode: Key.Mode) {
        let fretboard = Fretboard(tuning: setup.0.tuning, capo: setup.1)
        for key in Key.appKeys(mode) {
            for system in Position.System.allCases {
                for theme in fretboard.positions(of: key.scale, system: system) {
                    check(theme, on: fretboard)
                }
            }
        }
    }

    /// The pentatonic and blues scales too, in a key of each mode.
    @Test(arguments: setups)
    func otherScalesToo(preset: TuningPreset, capo: Int) {
        let fretboard = Fretboard(tuning: preset.tuning, capo: capo)
        for key in [Key.major(.d), .minor(.fSharp)] {
            for kind in Scale.Kind.allCases where kind.mode == key.mode && !kind.isSevenNote {
                for theme in fretboard.cagedPositions(of: Scale(kind, in: key)) { check(theme, on: fretboard) }
            }
        }
    }

    /// One expectation per theme, since thousands are checked. Going up (as sessions do), and down too in standard
    /// tuning without a capo, to keep the suite quick.
    private func check(_ theme: Position, on fretboard: Fretboard) {
        let isStandard = fretboard.tuning == TuningPreset.standard.tuning && fretboard.capo == 0
        for direction in isStandard ? PassDirection.allCases : [.up] {
            let circle = fretboard.scaleCirclePositions(from: theme, going: direction)
            #expect(problems(in: circle, from: theme, on: fretboard).isEmpty,
                    "\(theme.scale.name) \(theme.name) \(theme.frets) going \(direction)")
        }
    }

    private func problems(in circle: [Position], from theme: Position, on fretboard: Fretboard) -> [String] {
        guard circle.count == 12, let first = circle.first else { return ["\(circle.count) positions"] }
        var problems: [String] = []
        if circle.map(\.scale.key) != theme.scale.key.circleOfFifths { problems.append("keys") }
        if !circle.allSatisfy({ $0.scale.kind == theme.scale.kind && $0.system == first.system }) { problems.append("scale") }
        if first.id.number != theme.id.number { problems.append("first position") }
        if theme.frets.lowerBound > fretboard.capo + 2, first != theme { problems.append("moved") }
        let range = first.frets
        for position in circle {
            let width = position.frets.count
            if position.frets.lowerBound < range.lowerBound - width || position.frets.upperBound > range.upperBound + width {
                problems.append("\(position.scale.key) far: \(position.frets)")
            }
            let hasRoot = position.locations.contains {
                fretboard.pitch(at: $0).pitchClass == position.scale.tonic.pitchClass && range.contains($0.fret)
            }
            if !hasRoot { problems.append("\(position.scale.key) no root in range") }
        }
        return problems
    }
}
