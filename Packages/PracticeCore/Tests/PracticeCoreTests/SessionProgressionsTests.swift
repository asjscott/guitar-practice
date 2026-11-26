import Testing
import TheoryCore
import PracticeCore

private let fretboard = Fretboard(tuning: .standard)
private let progression = Progression.named("I–V–vi–IV")!

/// I–V–vi–IV in G, in G major's E shape, at 60 BPM.
private func themed() -> DrillSetup {
    var setup = DrillSetup(fretboard: fretboard, seed: 1)
    setup.follow(Theme(key: .major(.g), position: .init(system: .caged, number: CAGEDShape.e.number), stringSet: .dGB,
                       progression: progression))
    setup.options.backing = BackingSettings(tempo: 60)
    return setup
}

/// A 3-minute Nearest voicing block from 100 s, then another block. Its backing counts in from 100 s; time through k
/// (from 0) is G, D, Em and C from 104 + 16k s, a bar each. 30 s are left at 250 s, in the time through from 248 s
/// to 264 s.
private func playing(hasSound: Bool = true) -> SessionPlayer {
    var player = SessionPlayer(blocks: [.nearestVoicing, .notePlayIt].map { SessionBlock(kind: $0, length: s(180)) },
                               setup: themed(), hasSound: hasSound)
    player.handle(.start(at: s(99)))
    player.handle(.next(at: s(100)))
    return player
}

private func backing(at start: Double) -> Backing {
    Backing(chords: progression.chords(in: .major(.g)).map { BackingChord($0) }, style: .rock, bpm: 60, start: s(start))
}

extension SessionPlayer {
    fileprivate mutating func tick(_ time: Double) { handle(.tick(at: s(time))) }

    /// Each chord's first voicing in the position, a note a beat from the chord's first beat, for the times through from
    /// `start` s.
    fileprivate mutating func playCleanly(from start: Double, timesThrough: Int) {
        let position = Theme(key: .major(.g), position: .init(system: .caged, number: CAGEDShape.e.number))
            .position(on: fretboard)!
        var previous: TriadVoicing?
        for place in 0..<(4 * timesThrough) {
            let chord = progression.chords(in: .major(.g))[place % 4]
            let voicing = previous.map { fretboard.nearestVoicings(of: chord, in: position, to: $0)[0] }
                ?? fretboard.voicings(of: chord, in: position)[0]
            previous = voicing
            for (note, location) in voicing.locations.enumerated() {
                let onset = start + Double(place * 4 + note)
                handle(.played(fretboard.pitch(at: location), onset: s(onset), at: s(onset + 0.05)))
            }
        }
    }

    fileprivate var block: SessionSummary.Block? { summary.blocks.first }
}

@Suite("Progressions in a session")
struct SessionProgressionsTests {
    @Test func theBlockPlaysTheThemesProgressionOverBacking() {
        var player = playing()
        #expect(player.takeBacking() == [.start(backing(at: 100))])
        #expect(player.display?.headline == "G  D  Em  C")
        player.handle(.backingStarted(backing(at: 100.2)))
        player.playCleanly(from: 104.2, timesThrough: 1)
        player.tick(120.5)
        #expect(player.attempts(inBlock: 0).compactMap(\.chord).map(\.outcome) == [.clean, .clean, .clean, .clean])
    }

    @Test func pausingStopsTheBackingAndResumingCountsIn() {
        var player = playing()
        _ = player.takeBacking()
        player.handle(.pause(at: s(110)))
        #expect(player.takeBacking() == [.stop])
        player.handle(.resume(at: s(130)))
        #expect(player.takeBacking() == [.start(backing(at: 130))])
    }

    @Test func endingTheBlockStopsTheBacking() {
        var player = playing()
        _ = player.takeBacking()
        player.handle(.next(at: s(150)))
        #expect(player.takeBacking() == [.stop])
    }

    @Test func aDueChimeWaitsForTheEndOfTheTimeThroughAndTheNextCountsInAfterIt() {
        var player = playing()
        _ = player.takeBacking()
        player.tick(250.1)
        #expect(player.takeChime() == nil)
        // The backing stops when the time through ends, and counts in again once the chime would be over.
        #expect(player.takeBacking() == [.end(at: s(264))])
        player.tick(263.9)
        #expect(player.takeChime() == nil)
        player.tick(264.02)
        #expect(player.takeChime() == .chime)
        player.handle(.soundStarted(.chime, at: s(264.02), latency: s(0.1)))
        player.tick(264.3)
        #expect(player.takeBacking() == [.start(backing(at: 264.02 + 0.1 + 0.9 + 0.3))])
        player.tick(265.5)
        #expect(player.takeBacking().isEmpty)
        // Ten times through, and nothing yet of the next.
        player.tick(270)
        #expect(player.attempts(inBlock: 0).count == 40)
    }

    @Test func notesOfTheTimeThroughBeforeTheChimeStillCount() {
        var player = playing()
        player.handle(.backingStarted(backing(at: 100)))
        player.tick(250.1)
        player.playCleanly(from: 248, timesThrough: 1)
        player.tick(264.3)
        let last = player.attempts(inBlock: 0).suffix(4).compactMap(\.chord)
        #expect(last.map(\.outcome) == [.clean, .clean, .clean, .clean])
    }

    @Test func withoutSoundItFlashesAtOnce() {
        var player = playing(hasSound: false)
        player.tick(250.1)
        #expect(player.takeChime() == .chime)
    }

    @Test func theSummaryHasTheChords() throws {
        var player = playing()
        player.handle(.backingStarted(backing(at: 100)))
        player.playCleanly(from: 104, timesThrough: 2)
        player.tick(136.5)
        player.handle(.next(at: s(137)))
        let chords = try #require(player.block?.chords)
        #expect(chords.clean == 8)
        #expect(chords.timesThrough == 2)
        #expect(player.block?.passes == nil)
    }

    @Test func otherBlocksHaveNoChords() {
        var player = SessionPlayer(blocks: [SessionBlock(kind: .notePlayIt, length: s(60))], setup: themed())
        player.handle(.start(at: s(0)))
        player.handle(.next(at: s(1)))
        player.handle(.next(at: s(10)))
        #expect(player.summary.blocks.first?.chords == nil)
    }
}
