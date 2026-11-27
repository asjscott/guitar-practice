import Testing
import TheoryCore
import PracticeCore

/// I–V–vi–IV in G, in G major's E shape, at 60 BPM, as a theme.
private func themed() -> DrillSetup {
    var setup = DrillSetup(fretboard: Fretboard(tuning: .standard), seed: 1)
    setup.follow(Theme(key: .major(.g), position: .init(system: .caged, number: CAGEDShape.e.number), stringSet: .dGB,
                       progression: Progression.named("I–V–vi–IV")!))
    setup.options.backing = BackingSettings(tempo: 60)
    return setup
}

/// A block of the kind playing from 100 s.
private func playing(_ kind: DrillKind, hasSound: Bool = true) -> SessionPlayer {
    var player = SessionPlayer(blocks: [SessionBlock(kind: kind, length: s(180))], setup: themed(), hasSound: hasSound)
    player.handle(.start(at: s(99)))
    player.handle(.next(at: s(100)))
    return player
}

@Suite("Chords in position and Free time in a session")
struct SessionChordsAndFreeTimeTests {
    @Test func chordsInPositionFollowsTheThemeAndItsBlockSummarisesChords() throws {
        var player = playing(.chordsInPosition)
        let display = try #require(player.display)
        #expect(display.headline == "G")
        #expect(player.takeBacking().isEmpty)
        player.handle(.skip(at: s(101)))
        player.handle(.next(at: s(102)))
        let block = try #require(player.summary.blocks.first)
        #expect(block.chords?.chords == 1)
    }

    @Test func freeTimeLoopsTheThemesBackingAndHasNoChordSummary() throws {
        var player = playing(.freeTime)
        let requests = player.takeBacking()
        guard case .start(let backing) = try #require(requests.first) else { Issue.record("no backing"); return }
        #expect(backing.start == s(100))
        player.handle(.tick(at: s(400)))
        player.handle(.next(at: s(401)))
        let block = try #require(player.summary.blocks.first)
        #expect(block.stats.attempts.isEmpty)
        #expect(block.chords == nil)
    }

    @Test func withoutSoundFreeTimeIsLeftOut() {
        let player = playing(.freeTime, hasSound: false)
        #expect(player.isLeftOut(block: 0))
    }
}
