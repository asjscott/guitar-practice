import Testing
import TheoryCore
import PracticeCore

private func themed(_ set: StringSet = .dGB, seed: UInt64 = 1) -> DrillSetup {
    var setup = DrillSetup(fretboard: Fretboard(tuning: .standard), seed: seed)
    setup.follow(Theme(key: .minor(.a), position: .init(system: .caged, number: 5), stringSet: set))
    return setup
}

/// 3-minute blocks, the first playing from 100 s: 30 s are left at 250 s.
private func playing(_ kind: DrillKind, hasSound: Bool = true) -> SessionPlayer {
    var player = SessionPlayer(blocks: [kind, .notePlayIt].map { SessionBlock(kind: $0, length: s(180)) }, setup: themed(),
                               hasSound: hasSound)
    player.handle(.start(at: s(99)))
    player.handle(.next(at: s(100)))
    return player
}

extension SessionPlayer {
    /// The right note. For the first of a voicing, the lowest one that is in a voicing.
    fileprivate mutating func playNote(at time: Double) {
        guard let drill, let prompt = drill.prompt else { return }
        let locations = prompt.target.map { [$0] } ?? (0...12).map { FretboardLocation(string: prompt.string, fret: $0) }
        for pitch in locations.map(drill.fretboard.pitch(at:)) where pitch.pitchClass == prompt.pitchClass {
            var copy = drill
            copy.handle(.played(pitch, onset: s(time), at: s(time)))
            if copy.attempts.count > drill.attempts.count {
                return handle(.played(pitch, onset: s(time), at: s(time)))
            }
        }
    }

    fileprivate mutating func playChime(at time: Double) -> AppSound? {
        let chime = takeChime()
        if let chime { handle(.soundStarted(chime, at: s(time), latency: s(0.1))) }
        return chime
    }

    fileprivate var notes: [String]? { display?.chips.map(\.text) }
}

private let drills = [DrillKind.triadPlayIt, .inversions]

@Suite("Triads in a session: what is asked")
struct SessionTriadPromptTests {
    /// The theme's position is at frets 5–8.
    @Test(arguments: drills)
    func onlyTheThemesSetAndTheKeysChordsAnywhereInTheRange(kind: DrillKind) {
        var triads: Set<TriadFacts> = [], frets: Set<Int> = []
        for seed in UInt64(0)..<40 {
            let setup = themed(.aDG, seed: seed)
            var drill = kind.makeDrill(setup)
            drill.handle(.start(at: s(0)))
            for index in 1...5 {
                drill.handle(.tick(at: s(Double(index) * 11)))
                frets.formUnion(drill.display?.markers.map(\.location.fret) ?? [])
                drill.handle(.skip(at: s(Double(index) * 11 + 0.1)))
            }
            for case .triad(let facts) in drill.attempts.compactMap(\.facts) { triads.insert(facts) }
        }
        #expect(Set(triads.map(\.stringSet)) == [.aDG])
        #expect(Set(triads.map(\.triad.name)) == ["A minor", "C major", "D minor", "E minor", "F major", "G major"])
        #expect(frets.contains { $0 < 4 } && frets.contains { $0 > 9 } && !frets.contains { $0 > 12 })
    }

    @Test func naturalsDoesNotApply() {
        var setup = DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1)
        setup.follow(Theme(key: .major(.dFlat), position: .init(system: .caged, number: 1), stringSet: .gBE))
        setup.options.notes = .naturals
        var drill = DrillKind.triadPlayIt.makeDrill(setup)
        drill.handle(.start(at: s(0)))
        for index in 1...40 { drill.handle(.skip(at: s(Double(index)))) }
        #expect(Set(drill.attempts.map(\.prompt.noteName)).isSuperset(of: ["D♭", "E♭", "A♭"]))
    }
}

@Suite("Triads in a session: chimes")
struct SessionTriadChimeTests {
    /// A chime due while a voicing has one note played.
    private func partWay(_ kind: DrillKind, hasSound: Bool = true) -> SessionPlayer {
        var player = playing(kind, hasSound: hasSound)
        player.handle(.skip(at: s(248)))
        player.playNote(at: 249)
        player.handle(.tick(at: s(251)))
        #expect(player.takeChime() == nil)
        return player
    }

    @Test(arguments: drills)
    func aChimeWaitsForTheVoicingsEnd(kind: DrillKind) {
        var player = partWay(kind)
        player.playNote(at: 252)
        #expect(player.takeChime() == nil)
        #expect(player.notes?.filter { $0 == "?" }.count == 1)
        player.playNote(at: 253)
        #expect(player.drill?.attempts.suffix(3).map(\.outcome) == [.answered, .answered, .answered])
        #expect(player.playChime(at: 253) == .chime)        // until 253 + 0.1 + 0.9 + 0.3
        player.handle(.tick(at: s(254.2)))
        #expect(player.display?.result == .right)
        player.handle(.tick(at: s(254.4)))
        #expect(player.drill?.phase == .waiting)
        #expect(player.notes == ["?", "?", "?"])
        #expect(player.drill?.promptStart == s(254.4))
    }

    @Test(arguments: drills)
    func skippingPartWayMakesAGap(kind: DrillKind) {
        var player = partWay(kind)
        player.handle(.skip(at: s(252)))
        #expect(player.playChime(at: 252) == .chime)
        player.handle(.tick(at: s(253.4)))
        #expect(player.drill?.phase == .waiting)
        #expect(player.notes == ["?", "?", "?"])
        #expect((player.drill?.promptStart).map { $0 >= s(253.3) } == true)
    }

    @Test(arguments: drills)
    func aTimeoutPartWayMakesAGap(kind: DrillKind) {
        var player = partWay(kind)
        player.handle(.tick(at: s(259.3)))
        #expect(player.drill?.phase == .timedOut)
        #expect(player.takeChime() == .chime)
    }

    @Test(arguments: drills)
    func withoutSoundItFlashesBetweenVoicings(kind: DrillKind) {
        var player = partWay(kind, hasSound: false)
        player.playNote(at: 252)
        #expect(player.takeChime() == nil)
        player.playNote(at: 253)
        #expect(player.takeChime() == .chime)
    }

    @Test func heldThroughAPauseAClimbStartsItsVoicingAgainAfterIt() {
        var player = partWay(.inversions)
        let place = player.drill?.attempts.last?.group?.place
        player.handle(.pause(at: s(252)))
        player.handle(.resume(at: s(260)))
        #expect(player.playChime(at: 260) == .chime)
        #expect(player.notes == ["?", "?", "?"])
        #expect(player.drill?.timeRemaining(at: s(261)) == nil)
        player.handle(.tick(at: s(261.4)))
        #expect(player.drill?.promptStart == s(261.3))
        player.playNote(at: 262)
        #expect(player.drill?.attempts.last?.group?.place == place)
    }
}

@Suite("Triads in a session: summary")
struct SessionTriadSummaryTests {
    @Test func promptsFirstTryMedianTimeAndSkips() throws {
        var player = playing(.triadPlayIt)
        for time in [101.0, 102, 103] { player.playNote(at: time) }         // 3 s
        player.handle(.tick(at: s(104)))
        player.handle(.played(Pitch(30), onset: s(105), at: s(105)))
        for time in [108.0, 109, 110] { player.playNote(at: time) }         // 6 s
        player.handle(.tick(at: s(111)))
        player.playNote(at: 112)
        player.handle(.skip(at: s(113)))
        player.handle(.skip(at: s(114)))        // none of it done, so not a prompt
        player.handle(.end(at: s(115)))
        let block = try #require(player.summary.blocks.first)
        #expect(block.stats.prompts == 3)
        #expect(block.stats.skips == 2)
        #expect(block.stats.firstTryAccuracy == 6.0 / 7)
        #expect(block.medianVoicingTime == s(4.5))
        #expect(block.speedText == "4.50 s a voicing")
        #expect(block.passes == nil)
    }

    @Test func aClimbIsOnePromptTimedByVoicing() throws {
        var player = playing(.inversions)
        for time in [102.0, 103, 104] { player.playNote(at: time) }         // 4 s
        player.handle(.tick(at: s(105)))
        for time in [106.0, 107] { player.playNote(at: time) }
        player.handle(.pause(at: s(108)))
        player.handle(.resume(at: s(120)))      // the same voicing, from its first note
        for time in [121.0, 122, 122.5] { player.playNote(at: time) }       // 2.5 s
        player.handle(.end(at: s(123)))
        let block = try #require(player.summary.blocks.first)
        #expect(block.stats.prompts == 1)
        #expect(block.stats.attempts.count == 8)
        #expect(block.medianVoicingTime == s(3.25))
    }

    @Test func withNoVoicingPlayedWholeThereIsNoTime() {
        var player = playing(.triadPlayIt)
        player.playNote(at: 101)
        player.handle(.end(at: s(102)))
        #expect(player.summary.blocks[0].speedText == nil)
    }

    @Test func otherBlocksHaveNone() {
        var player = playing(.notePlayIt)
        player.handle(.end(at: s(102)))
        #expect(player.summary.blocks[0].medianVoicingTime == nil)
    }
}
