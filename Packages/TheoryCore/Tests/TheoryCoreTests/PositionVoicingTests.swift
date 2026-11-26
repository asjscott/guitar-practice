import Testing
import TheoryCore

private func frets(_ voicing: TriadVoicing) -> [Int] { voicing.locations.map(\.fret) }

/// G major's E shape in standard tuning, frets 2–5, by string from 6:
/// [2 3 5] [2 3 5] [2 4 5] [2 4 5] [3 5] [2 3 5].
@Suite("Voicings in the position, standard tuning")
struct StandardPositionVoicingTests {
    let fretboard = Fretboard(tuning: .standard)
    let gMajor = Triad(.major, root: .g)
    let dMajor = Triad(.major, root: .d)

    func eShape() throws -> Position {
        try #require(fretboard.cagedPositions(of: Scale(.major, tonic: .g)).first { $0.cagedShape == .e && $0.octave == 0 })
    }

    @Test func gMajorInGsEShapeHasThreeVoicingsUpTheNeck() throws {
        let voicings = fretboard.voicings(of: gMajor, in: try eShape())
        #expect(voicings.map(\.stringSet) == [.gBE, .dGB, .aDG])
        #expect(voicings.map(\.inversion) == [.first, .root, .second])
        #expect(voicings.map(frets) == [[4, 3, 3], [5, 4, 3], [5, 5, 4]])
    }

    @Test func dMajorInGsEShapeHasOneOnEachStringSet() throws {
        let voicings = fretboard.voicings(of: dMajor, in: try eShape())
        #expect(Set(voicings.map(\.stringSet)) == Set(StringSet.allCases))
        #expect(Set(voicings.map(frets)) == [[5, 5, 4], [5, 4, 2], [4, 2, 3], [2, 3, 2]])
    }

    @Test func movementSumsEachVoicesSemitones() throws {
        let position = try eShape()
        let g = try #require(fretboard.voicings(of: gMajor, in: position).first { $0.stringSet == .dGB })
        let ds = fretboard.voicings(of: dMajor, in: position)
        let byFrets = Dictionary(uniqueKeysWithValues: ds.map { (frets($0), fretboard.movement(from: g, to: $0)) })
        // G D B on 55 59 62; D F♯ A voicings: 45 50 54, 50 54 57, 54 57 62, 57 62 66.
        #expect(byFrets == [[5, 5, 4]: 27, [5, 4, 2]: 15, [4, 2, 3]: 3, [2, 3, 2]: 9])
        #expect(fretboard.movement(from: g, to: g) == 0)
    }

    @Test func theNearestDFromEachGVoicing() throws {
        let position = try eShape()
        let gs = fretboard.voicings(of: gMajor, in: position)
        let nearest = gs.map { fretboard.nearestVoicings(of: dMajor, in: position, to: $0).map(frets) }
        #expect(nearest == [[[2, 3, 2]], [[4, 2, 3]], [[5, 4, 2]]])
    }

    @Test func theMiddleVoicingIsNearestThePositionsCentre() throws {
        let position = try eShape()
        #expect(fretboard.middleVoicing(of: gMajor, in: position).map(frets) == [5, 4, 3])
    }

    @Test func everyProgressionFitsEveryCAGEDShapeOfEveryKey() {
        for key in Key.appMajorKeys + Key.appMinorKeys {
            for position in fretboard.cagedPositions(of: key.scale) {
                for progression in Progression.library(key.mode) {
                    #expect(fretboard.fits(progression, in: key, position: position), "\(progression.id) in \(key)")
                }
            }
        }
    }
}

@Suite("Voicings in the position, other tunings and a capo")
struct PositionVoicingInvariantTests {
    static let fretboards: [Fretboard] = [
        Fretboard(tuning: TuningPreset.dropD.tuning), Fretboard(tuning: TuningPreset.dadgad.tuning),
        Fretboard(tuning: TuningPreset.openG.tuning), Fretboard(tuning: .standard, capo: 3),
        Fretboard(tuning: TuningPreset.dropD.tuning, capo: 5),
    ]

    @Test(arguments: fretboards)
    func voicingsStayInThePositionAndNearestIsLeastMovement(fretboard: Fretboard) {
        for key in Key.appMajorKeys + Key.appMinorKeys {
            for position in fretboard.cagedPositions(of: key.scale) {
                let inPosition = Set(position.locations)
                for progression in Progression.library(key.mode) {
                    let chords = progression.chords(in: key)
                    let all = chords.map { fretboard.voicings(of: $0, in: position) }
                    #expect(fretboard.fits(progression, in: key, position: position) == all.allSatisfy { !$0.isEmpty })
                    for voicing in all.joined() {
                        #expect(voicing.locations.allSatisfy(inPosition.contains))
                        #expect(voicing.frets.count <= Fretboard.maxTriadVoicingSpan)
                        #expect(voicing.locations.allSatisfy { fretboard.isPlayable($0) })
                    }
                    for index in chords.indices.dropLast() {
                        let next = all[index + 1]
                        for voicing in all[index] {
                            let nearest = fretboard.nearestVoicings(of: chords[index + 1], in: position, to: voicing)
                            guard let least = nearest.first.map({ fretboard.movement(from: voicing, to: $0) }) else {
                                #expect(next.isEmpty)
                                continue
                            }
                            #expect(nearest.allSatisfy { fretboard.movement(from: voicing, to: $0) == least })
                            #expect(next.allSatisfy { fretboard.movement(from: voicing, to: $0) >= least })
                            #expect(Set(nearest) == Set(next.filter { fretboard.movement(from: voicing, to: $0) == least }))
                        }
                    }
                }
            }
        }
    }

    @Test func someOpenTuningPositionsLeaveProgressionsOut() {
        let dadgad = Fretboard(tuning: TuningPreset.dadgad.tuning)
        let misfits = (Key.appMajorKeys + Key.appMinorKeys).flatMap { key in
            dadgad.cagedPositions(of: key.scale).flatMap { position in
                Progression.library(key.mode).filter { !dadgad.fits($0, in: key, position: position) }
            }
        }
        #expect(!misfits.isEmpty)
    }
}
