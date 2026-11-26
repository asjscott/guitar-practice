import PracticeCore
import TheoryCore
import Testing

private func major(_ root: NoteName) -> Triad { Triad(.major, root: root) }
private func minor(_ root: NoteName) -> Triad { Triad(.minor, root: root) }

/// I–V–vi–IV in G, a bar each.
private let gDEmC = [BackingChord(major(.g)), BackingChord(major(.d)), BackingChord(minor(.e)), BackingChord(major(.c))]

/// At 60 BPM a beat is a second, so beats can be read off the times.
private func rock(_ chords: [BackingChord] = gDEmC, bpm: Int = 60, start: Duration = .seconds(10)) -> Backing {
    Backing(chords: chords, style: .rock, bpm: bpm, start: start)
}

private func backing(_ style: BackingStyle, _ chords: [BackingChord] = gDEmC, bpm: Int = 60) -> Backing {
    Backing(chords: chords, style: style, bpm: bpm, start: .seconds(10))
}

private func beats(_ notes: [BackingNote], at bpm: Int = 60, from start: Duration) -> [Double] {
    notes.map { (($0.time - start) / .seconds(60) * Double(bpm) * 1000).rounded() / 1000 }
}

@Suite("Backing as data")
struct BackingTests {
    @Test func theCountInIsABarOfDrumsticksOnTheBeats() {
        let countIn = rock().countIn
        #expect(countIn.allSatisfy { $0.part == .drums && $0.pitch == Backing.Drum.sticks })
        #expect(beats(countIn, from: .seconds(10)) == [0, 1, 2, 3])
    }

    /// Four bars after the bar of count-in: beats 4 to 19 from its start.
    @Test func rockDrumsKickOn1And3SnareOn2And4AndEighthHiHats() {
        let drums = rock().timeThrough.filter { $0.part == .drums }
        let on = { (drum: Pitch) in beats(drums.filter { $0.pitch == drum }, from: .seconds(10)) }
        #expect(on(Backing.Drum.kick) == [4, 6, 8, 10, 12, 14, 16, 18])
        #expect(on(Backing.Drum.snare) == [5, 7, 9, 11, 13, 15, 17, 19])
        #expect(on(Backing.Drum.closedHiHat) == Array(stride(from: 4.0, to: 20, by: 0.5)))
        #expect(on(Backing.Drum.sticks) == [])
    }

    /// The root an octave or so below the guitar's low E, from E1 up: G1, D2, E1, C2.
    @Test func rockBassPlaysEighthsOnEachChordsRoot() {
        let bass = rock().timeThrough.filter { $0.part == .bass }
        #expect(beats(bass, from: .seconds(10)) == Array(stride(from: 4.0, to: 20, by: 0.5)))
        #expect(bass.map(\.pitch.midi) == [31, 38, 28, 36].flatMap { Array(repeating: $0, count: 8) })
    }

    /// Each chord's three tones, each the lowest from G3 up, so they stay within G3–F♯4.
    @Test func rockKeysPlayTheTriadOnBeats1And3InTheMiddleRegister() {
        let keys = rock().timeThrough.filter { $0.part == .keys }
        #expect(beats(keys, from: .seconds(10)) == [4, 6, 8, 10, 12, 14, 16, 18].flatMap { Array(repeating: $0, count: 3) })
        let chords = stride(from: 0, to: keys.count, by: 3).map { keys[$0..<$0 + 3].map(\.pitch.midi).sorted() }
        let g = [55, 59, 62], d = [57, 62, 66], em = [55, 59, 64], c = [55, 60, 64]
        #expect(chords == [g, g, d, d, em, em, c, c])
    }

    @Test(arguments: [40, 70, 160])
    func rockKeysHoldUntilTheNextAndNothingOutlastsItsBar(_ bpm: Int) {
        let backing = rock(bpm: bpm)
        let beat = Duration.seconds(60) / bpm
        let keys = backing.timeThrough.filter { $0.part == .keys }
        #expect(keys.allSatisfy { $0.length > beat * 1.5 && $0.length < beat * 2 })
        let end = backing.start + beat * 4 * (1 + backing.barsPerTimeThrough)
        #expect(backing.timeThrough.allSatisfy { $0.time + $0.length <= end })
    }

    @Test func afterTheCountInTheProgressionGoesRoundAndRound() {
        let backing = rock()
        let bass = backing.notes(from: .seconds(10), before: .seconds(10 + 44)).filter { $0.part == .bass }
        // Four bars a time through, from beat 4: G at 4, 20 and 36; C in the bars from 16, 32 and 48 (cut off at 44).
        let roots = Dictionary(grouping: bass) { Int(beats([$0], from: .seconds(10))[0]) / 4 * 4 }.mapValues { $0[0].pitch.midi }
        #expect(roots == [4: 31, 8: 38, 12: 28, 16: 36, 20: 31, 24: 38, 28: 28, 32: 36, 36: 31, 40: 38])
        #expect(backing.notes(from: .seconds(10), before: .seconds(30)).filter { $0.pitch == Backing.Drum.sticks }.count == 4)
    }

    /// As the app asks for them, a second or so at a time: every note once, in order.
    @Test func notesAskedForInStretchesAreEachGivenOnce() {
        let backing = rock(bpm: 70, start: .milliseconds(10_123))
        var stretches: [BackingNote] = []
        var time = Duration.seconds(9)
        while time < .seconds(40) {
            stretches += backing.notes(from: time, before: time + .milliseconds(700))
            time += .milliseconds(700)
        }
        #expect(stretches == backing.notes(from: .seconds(9), before: time))
        #expect(stretches.map(\.time) == stretches.map(\.time).sorted())
        #expect(Array(stretches.prefix(4)) == backing.countIn)
        #expect(Array(stretches.dropFirst(4).prefix(backing.timeThrough.count)) == backing.timeThrough)
    }

    @Test func aChordOfTwoBarsKeepsItsRootForBoth() {
        let ii = BackingChord(minor(.a)), v = BackingChord(major(.d)), i = BackingChord(major(.g), bars: 2)
        let bass = rock([ii, v, i]).timeThrough.filter { $0.part == .bass }
        #expect(bass.map(\.pitch.midi) == [33, 38, 31, 31].flatMap { Array(repeating: $0, count: 8) })
    }

    // MARK: - Pop ballad

    /// Half time: the snare on 3 only, so a bar feels like two slow beats.
    @Test func popBalladDrumsKickOn1SnareOn3AndHiHatsOnTheBeats() {
        let drums = backing(.popBallad).timeThrough.filter { $0.part == .drums }
        let on = { (drum: Pitch) in beats(drums.filter { $0.pitch == drum }, from: .seconds(10)) }
        #expect(on(Backing.Drum.kick) == [4, 8, 12, 16])
        #expect(on(Backing.Drum.snare) == [6, 10, 14, 18])
        #expect(on(Backing.Drum.closedHiHat) == Array(stride(from: 4.0, to: 20, by: 1)))
    }

    /// The root on 1 and its fifth above on 3: G1 D2, D2 A2, E1 B1, C2 G2.
    @Test func popBalladBassPlaysRootOn1AndFifthOn3() {
        let bass = backing(.popBallad).timeThrough.filter { $0.part == .bass }
        #expect(beats(bass, from: .seconds(10)) == Array(stride(from: 4.0, to: 20, by: 2)))
        #expect(bass.map(\.pitch.midi) == [31, 38, 38, 45, 28, 35, 36, 43])
    }

    /// One chord a bar, held nearly to the next, in the same middle register as rock's.
    @Test(arguments: [60, 120])
    func popBalladKeysHoldEachChordForItsBar(_ bpm: Int) {
        let ballad = backing(.popBallad, bpm: bpm)
        let bar = Duration.seconds(60) / bpm * 4
        let keys = ballad.timeThrough.filter { $0.part == .keys }
        #expect(beats(keys, at: bpm, from: .seconds(10)) == [4, 8, 12, 16].flatMap { Array(repeating: $0, count: 3) })
        #expect(keys.allSatisfy { $0.length > bar * 0.9 && $0.length < bar })
        let chords = stride(from: 0, to: keys.count, by: 3).map { keys[$0..<$0 + 3].map(\.pitch.midi).sorted() }
        #expect(chords == [[55, 59, 62], [57, 62, 66], [55, 59, 64], [55, 60, 64]])
    }

    // MARK: - Blues shuffle

    /// Shuffled eighths: the second of each beat's pair two thirds of the way through it.
    @Test func bluesShuffleDrumsKickOn1And3SnareOn2And4AndShuffledHiHats() {
        let drums = backing(.bluesShuffle).timeThrough.filter { $0.part == .drums }
        let on = { (drum: Pitch) in beats(drums.filter { $0.pitch == drum }, from: .seconds(10)) }
        #expect(on(Backing.Drum.kick) == [4, 6, 8, 10, 12, 14, 16, 18])
        #expect(on(Backing.Drum.snare) == [5, 7, 9, 11, 13, 15, 17, 19])
        #expect(on(Backing.Drum.closedHiHat) == (4..<20).flatMap { [Double($0), Double($0) + 0.667] })
    }

    /// Root, fifth, sixth, fifth, a beat each in shuffled pairs: in G, G1 D2 E2 D2.
    @Test func bluesShuffleBassWalksRootFifthSixthInShuffledEighths() {
        let bass = backing(.bluesShuffle).timeThrough.filter { $0.part == .bass }
        #expect(beats(bass, from: .seconds(10)) == (4..<20).flatMap { [Double($0), Double($0) + 0.667] })
        #expect(Array(bass.prefix(8).map(\.pitch.midi)) == [31, 31, 38, 38, 40, 40, 38, 38])
        // C: C2 G2 A2 G2.
        #expect(Array(bass.suffix(8).map(\.pitch.midi)) == [36, 36, 43, 43, 45, 45, 43, 43])
    }

    @Test(arguments: [BackingStyle.popBallad, .bluesShuffle])
    func everyStyleCountsInWithFourDrumsticks(_ style: BackingStyle) {
        let countIn = backing(style).countIn
        #expect(countIn.allSatisfy { $0.part == .drums && $0.pitch == Backing.Drum.sticks })
        #expect(beats(countIn, from: .seconds(10)) == [0, 1, 2, 3])
    }

    @Test(arguments: BackingStyle.allCases, [60, 120])
    func noStylesNoteOutlastsItsBar(_ style: BackingStyle, _ bpm: Int) {
        let styled = backing(style, bpm: bpm)
        let bar = Duration.seconds(60) / bpm * 4
        for (index, note) in styled.timeThrough.enumerated() {
            let barStart = styled.start + bar * Int((note.time - styled.start) / bar)
            #expect(note.time + note.length <= barStart + bar, "note \(index)")
        }
    }
}

@Suite("Backing style per progression")
struct BackingStyleDefaultTests {
    @Test func theTwelveBarBluesDefaultsToTheShuffleAndEveryOtherProgressionToRock() {
        let defaults = Dictionary(uniqueKeysWithValues: Progression.library.map { ($0.id, $0.defaultStyle) })
        #expect(defaults["12-bar blues"] == .bluesShuffle)
        #expect(defaults.filter { $0.key != "12-bar blues" }.values.allSatisfy { $0 == .rock })
        #expect(defaults.count == 8)
    }
}
