import Testing
import TheoryCore
import PracticeCore

private func themed(_ key: Key = .minor(.a), _ system: Position.System = .caged, number: Int = CAGEDShape.g.number,
                    on fretboard: Fretboard = Fretboard(tuning: .standard)) -> DrillSetup {
    var setup = DrillSetup(fretboard: fretboard, seed: 1)
    setup.options.pass.holdsTempo = true
    setup.follow(Theme(key: key, position: .init(system: system, number: number)))
    return setup
}

/// 3-minute blocks, the first playing from 100 s: in 4/4 at 60 BPM its first pass's beat 1 is at 104 s, 30 s are left
/// at 250 s and the planned end is at 280 s.
private func playing(_ kinds: [DrillKind] = [.upAndDown, .notePlayIt], setup: DrillSetup = themed(),
                     hasSound: Bool = true) -> SessionPlayer {
    var player = SessionPlayer(blocks: kinds.map { SessionBlock(kind: $0, length: s(180)) }, setup: setup, hasSound: hasSound)
    player.handle(.start(at: s(99)))
    player.handle(.next(at: s(100)))
    return player
}

private func track(_ start: Double, bpm: Int = 60) -> ClickTrack {
    ClickTrack(meter: Meter(.fourFour), bpm: bpm, start: s(start))
}

extension SessionPlayer {
    private var target: Pitch? { drill?.prompt?.target.map { drill!.fretboard.pitch(at: $0) } }

    /// Plays the rest of the pass, a note per second. Returns when the last was played.
    @discardableResult
    fileprivate mutating func playPass(from start: Double) -> Double {
        var time = start
        while let target, let pass = display?.pass, pass.notes.contains(where: { $0.state == .current }) {
            handle(.played(target, onset: s(time), at: s(time)))
            time += 1
        }
        return time - 1
    }

    fileprivate mutating func tick(_ time: Double) { handle(.tick(at: s(time))) }

    /// Skips to a fresh pass, so that none times out meanwhile.
    fileprivate mutating func skip(to time: Double) { handle(.skip(at: s(time))) }

    /// Which beat is counted in; nil if none.
    fileprivate var countIn: Int? { display?.pass?.countIn }

    fileprivate var scale: String? { if case .pass(let facts) = drill?.attempts.last?.facts { facts.scale.name } else { nil } }
}

@Suite("Scales in a session: what is played")
struct SessionScaleRotationTests {
    /// The scales of the first passes.
    private func scales(_ kind: DrillKind, _ setup: DrillSetup) -> [String?] {
        var drill = kind.makeDrill(setup)
        drill.handle(.start(at: s(0)))
        return (1...5).map { index in
            drill.handle(.skip(at: s(Double(index))))
            if case .pass(let facts) = drill.attempts.last?.facts { return facts.scale.name } else { return nil }
        }
    }

    @Test(arguments: [DrillKind.upAndDown, .fromADegree])
    func theScalesOfTheThemesModeInOrderAPassEach(kind: DrillKind) {
        #expect(scales(kind, themed(.major(.a)))
                == ["A major", "A major pentatonic", "A major", "A major pentatonic", "A major"])
        #expect(scales(kind, themed())
                == ["A natural minor", "A minor pentatonic", "A blues", "A natural minor", "A minor pentatonic"])
    }

    @Test func inTheThemesPosition() {
        let positions = themed().passPositions
        #expect(positions.map(\.id) == Array(repeating: .init(system: .caged, number: CAGEDShape.g.number), count: 3))
    }

    @Test func with3NPSTheSmallerScalesUseTheNearestCAGEDShape() {
        let setup = themed(.minor(.a), .threeNotesPerString, number: 1)
        let positions = setup.passPositions
        #expect(positions.map(\.system) == [.threeNotesPerString, .caged, .caged])
        let low = positions[0].frets.lowerBound
        for position in positions.dropFirst() {
            let nearest = setup.fretboard.cagedPositions(of: position.scale).map { abs($0.frets.lowerBound - low) }.min()
            #expect(abs(position.frets.lowerBound - low) == nearest)
        }
    }

    @Test func freePracticeKeepsToTheScaleChosen() {
        var setup = themed()
        setup.theme = nil
        setup.options.scaleKind = .blues
        #expect(Set(scales(.upAndDown, setup)) == ["A blues"])
    }

    @Test func eachScalesDegreesComeOnceBeforeAnyRepeats() {
        var drill = DrillKind.fromADegree.makeDrill(themed(.major(.a)))
        drill.handle(.start(at: s(0)))
        var degrees: [Scale.Kind: [Scale.Degree]] = [:]
        for index in 1...12 {
            drill.handle(.skip(at: s(Double(index))))
            if case .pass(let facts) = drill.attempts.last?.facts { degrees[facts.scale.kind, default: []].append(facts.startDegree) }
        }
        #expect(Set(degrees[.major] ?? []).count == 6)
        #expect(Set((degrees[.majorPentatonic] ?? []).prefix(4)).count == 4)
    }

    @Test func theHeaderNamesTheScale() {
        #expect(playing().display?.headline == "A natural minor · up and down")
        #expect(playing([.fromADegree]).display?.subline == "A natural minor · G shape")
    }

    @Test func resumeAndRKeepTheScaleAndSGoesOn() {
        var player = playing()
        player.handle(.repeat(at: s(101)))
        #expect(player.display?.headline.hasPrefix("A natural minor") == true)
        player.handle(.pause(at: s(102)))
        player.handle(.resume(at: s(103)))
        #expect(player.display?.headline.hasPrefix("A natural minor") == true)
        player.skip(to: 104)
        #expect(player.display?.headline.hasPrefix("A minor pentatonic") == true)
    }

    @Test func spelledInTheThemesKey() {
        #expect(DrillKind.upAndDown.makeDrill(themed(.minor(.dSharp))).setup.key == .minor(.dSharp))
    }

    @Test func naturalsAndTheFretRangeChangeNothing() {
        var setup = themed(.major(.a), number: CAGEDShape.c.number)
        let whole = setup.passPositions
        setup.options.notes = .naturals
        setup.options.frets = 0...1
        setup.options.strings = [0]
        #expect(setup.passPositions == whole)
        #expect(DrillKind.upAndDown.makeDrill(setup).nothingToPromptReason == nil)
    }

    @Test func noPositionOnTheNeckSaysSo() {
        let setup = themed(.major(.c), number: CAGEDShape.d.number, on: Fretboard(tuning: .standard, capo: 12))
        #expect(DrillKind.upAndDown.makeDrill(setup).nothingToPromptReason != nil)
        #expect(DrillKind.fromADegree.makeDrill(setup).nothingToPromptReason != nil)
    }
}

@Suite("Scales in a session: clicks and passes")
struct SessionPassTests {
    @Test func clicksStartWithTheBlockAndStopWithIt() {
        var player = playing()
        #expect(player.takeClicks() == [.start(track(100))])
        #expect(player.takeClicks().isEmpty)
        player.handle(.next(at: s(110)))
        #expect(player.takeClicks() == [.stop(at: s(110))])
        #expect(player.attempts(inBlock: 0).isEmpty)
        #expect(player.stage == .ready)
    }

    @Test func endingTheSessionStopsThem() {
        var player = playing()
        _ = player.takeClicks()
        player.handle(.end(at: s(110)))
        #expect(player.takeClicks() == [.stop(at: s(110))])
    }

    @Test func theyCountWhenHeard() {
        var player = playing()
        player.handle(.clicksStarted(track(100.2)))
        #expect(player.drill?.promptStart == s(104.2))
    }

    @Test func spaceDropsTheOpenPassButNotItsNotes() {
        var player = playing()
        let pitch = Pitch(45)
        player.handle(.played(pitch, onset: s(104), at: s(104.1)))
        player.handle(.next(at: s(105)))
        #expect(player.attempts(inBlock: 0).count == 1)
        #expect(player.summary.blocks[0].passes?.passes == 0)
    }

    @Test func resumeRestartsThePassWithItsCountIn() {
        var player = playing()
        player.handle(.played(Pitch(45), onset: s(104), at: s(104.1)))
        player.handle(.pause(at: s(105)))
        _ = player.takeClicks()
        player.handle(.resume(at: s(200)))
        #expect(player.takeClicks() == [.start(track(200))])
        #expect(player.drill?.promptStart == s(204))
        #expect(player.display?.pass?.notes.first?.state == .current)
    }

    @Test func theBlockNeverCutsOff() {
        var player = playing()
        for second in 101...400 { player.tick(Double(second)) }
        #expect(player.stage == .playing)
        #expect(player.blockIndex == 0)
        #expect(player.timeLeft(inBlock: 0) == s(-120))
        player.handle(.extend(at: s(400)))
        #expect(player.timeLeft(inBlock: 0) == .zero)
    }

    @Test func losingTheOutputPausesAndResumeGoesOnByTheBeats() {
        var player = playing()
        player.handle(.output(works: false, at: s(102)))
        #expect(player.stage == .paused)
        _ = player.takeClicks()
        player.handle(.resume(at: s(110)))
        #expect(player.stage == .playing)
        #expect(player.blockIndex == 0)
        #expect(player.takeClicks() == [.start(track(110))])
        player.tick(111)
        #expect(player.countIn == 2)
    }

    @Test func withoutSoundTheyStayInThePlan() {
        let kinds = SessionPlanner.drills(from: DrillKind.all, for: themed(), hasSound: false)
        #expect(kinds.contains(.upAndDown) && kinds.contains(.fromADegree))
        #expect(!playing(hasSound: false).isLeftOut(block: 0))
    }
}

@Suite("Scales in a session: chimes")
struct SessionPassChimeTests {
    /// A pass whose last note is at 251 s, the chime having been due since 250 s. Its bar ends
    /// at 253 s.
    private func passOver() -> SessionPlayer {
        var player = playing()
        player.skip(to: 225)
        let notes = player.display?.pass?.notes.count ?? 0
        let end = player.playPass(from: Double(252 - notes))
        #expect(end == 251)
        return player
    }

    /// Bars end every 4 s from 225 s.
    private let barEnd = 253.0

    @Test func noneDuringAPass() {
        var player = playing()
        player.skip(to: 246)
        player.tick(250.5)
        player.handle(.played(Pitch(45), onset: s(251), at: s(251.1)))
        player.handle(.played(Pitch(48), onset: s(252), at: s(252.1)))
        #expect(player.takeChime() == nil)
        #expect(player.drill?.attempts.filter { !$0.skipped }.isEmpty == false)
    }

    @Test func itWaitsForTheBarToEndAndTheCountInWaitsForIt() {
        var player = passOver()
        #expect(player.takeChime() == nil)
        // No click of the count-in is asked for before the chime would be over: 253 + 0.9 + 0.3.
        #expect(player.takeClicks().suffix(2) == [.stop(at: s(barEnd)), .start(track(barEnd + 1.2))])
        player.tick(252.9)
        #expect(player.takeChime() == nil)
        player.tick(253.02)
        #expect(player.takeChime() == .chime)
        player.handle(.soundStarted(.chime, at: s(253.02), latency: s(0.1)))
        #expect(player.takeClicks().last == .start(track(254.32)))
        player.tick(254.2)
        #expect(player.countIn == nil)
        #expect(player.takeChime() == nil)
        player.tick(254.4)
        #expect(player.countIn == 1)
        #expect(player.display?.headline.hasPrefix("A natural minor") == false)
        #expect(player.drill?.promptStart == s(258.32))
    }

    @Test func dueInTheGapItDoesToo() {
        var player = playing()
        player.skip(to: 221)
        let notes = player.display?.pass?.notes.count ?? 0
        // Bars end every 4 s from 221 s: the one with 249.5 s at 253 s.
        player.playPass(from: 249.5 - Double(notes - 1))
        #expect(player.takeChime() == nil)
        _ = player.takeClicks()
        player.tick(250.1)
        #expect(player.takeClicks() == [.stop(at: s(253)), .start(track(254.2))])
        player.tick(253)
        #expect(player.takeChime() == .chime)
    }

    @Test func notesPlayedOverItDontCount() {
        var player = passOver()
        player.tick(253)
        _ = player.takeChime()
        player.handle(.soundStarted(.chime, at: s(253), latency: .zero))
        let count = player.drill?.attempts.count
        player.handle(.played(Pitch(45), onset: s(253.5), at: s(253.6)))
        player.handle(.played(Pitch(45), onset: s(255), at: s(255.1)))
        #expect(player.drill?.attempts.count == count)
        #expect(player.drill?.phase == .waiting)
    }

    @Test func aSkipLetsItSoundBeforeTheNextCountIn() {
        var player = playing()
        player.skip(to: 246)
        player.tick(250.5)
        _ = player.takeClicks()
        player.skip(to: 251)
        #expect(player.takeChime() == .chime)
        player.handle(.soundStarted(.chime, at: s(251), latency: s(0.1)))
        #expect(player.takeClicks().last == .start(track(252.3)))
        player.tick(252.2)
        #expect(player.countIn == nil)
        player.tick(252.3)
        #expect(player.countIn == 1)
    }

    @Test func aChimeHeldThroughAPauseSoundsBeforeTheCountIn() {
        var player = playing()
        player.skip(to: 246)
        player.tick(250.5)
        player.handle(.pause(at: s(251)))
        #expect(player.takeChime() == nil)
        player.handle(.resume(at: s(300)))
        #expect(player.takeChime() == .chime)
        player.handle(.soundStarted(.chime, at: s(300), latency: .zero))
        #expect(player.takeClicks().last == .start(track(301.2)))
        player.tick(301.2)
        #expect(player.drill?.promptStart == s(305.2))
    }

    @Test func pausedBetweenPassesToo() {
        var player = passOver()
        player.handle(.pause(at: s(252)))
        player.handle(.resume(at: s(300)))
        #expect(player.takeChime() == .chime)
        player.handle(.soundStarted(.chime, at: s(300), latency: .zero))
        player.tick(301)
        #expect(player.countIn == nil)
        player.tick(301.3)
        #expect(player.drill?.promptStart == s(305.3))
    }

    @Test func aBlockStartedWhileItSoundsWaitsForItsEnd() {
        var player = playing([.notePlayIt, .upAndDown])
        player.handle(.soundStarted(.chime, at: s(200), latency: .zero))
        player.handle(.next(at: s(200.2)))
        player.handle(.next(at: s(200.4)))
        #expect(player.takeClicks().last == .start(track(201.2)))
        #expect(player.drill?.promptStart == s(205.2))
    }

    @Test func aFlashDelaysNothing() {
        var player = playing(hasSound: false)
        player.skip(to: 225)
        let notes = player.display?.pass?.notes.count ?? 0
        player.playPass(from: Double(252 - notes))
        #expect(player.takeChime() == .chime)
        player.tick(253)
        #expect(player.countIn == 1)
    }

    @Test func extendingDropsItAndOvertimeGoesOn() {
        var player = playing()
        player.skip(to: 246)
        player.tick(250.5)
        player.handle(.extend(at: s(251)))
        player.skip(to: 252)
        #expect(player.takeChime() == nil)
        player.skip(to: 399)
        player.tick(400.5)
        player.skip(to: 401)
        #expect(player.takeChime() == .softChime)
        #expect(player.timeLeft(inBlock: 0) < .zero)
    }
}

@Suite("Scales in a session: tempo and hints")
struct SessionPassSettingsTests {
    private func settings(_ tempo: Int) -> PassSettings {
        var settings = PassSettings()
        settings.tempo = tempo
        return settings
    }

    @Test func onTheReadyCardTheyAreForTheBlock() {
        var player = SessionPlayer(blocks: [SessionBlock(kind: .upAndDown, length: s(180))], setup: themed())
        #expect(player.passSettings == nil)
        player.handle(.start(at: s(99)))
        player.handle(.passSettings(settings(80), at: s(99.5)))
        #expect(player.passSettings?.tempo == 80)
        player.handle(.next(at: s(100)))
        #expect(player.takeClicks() == [.start(track(100, bpm: 80))])
    }

    @Test func eachDrillHasItsOwn() {
        var player = playing([.upAndDown, .fromADegree, .notePlayIt])
        player.handle(.passSettings(settings(100), at: s(101)))
        player.handle(.next(at: s(102)))
        #expect(player.passSettings?.tempo == 60)
        player.handle(.next(at: s(103)))
        player.handle(.next(at: s(104)))
        #expect(player.passSettings == nil)
        player.handle(.passSettings(settings(120), at: s(105)))
        #expect(player.passSettings == nil)
    }

    @Test func whilePausedTheyAreForTheRestartedPass() {
        var player = playing()
        player.handle(.pause(at: s(101)))
        player.handle(.passSettings(settings(90), at: s(102)))
        _ = player.takeClicks()
        player.handle(.resume(at: s(110)))
        #expect(player.takeClicks() == [.start(track(110, bpm: 90))])
    }

    @Test func theLadderMovesThem() {
        var setup = themed()
        setup.options.pass.holdsTempo = false
        var player = playing(setup: setup)
        player.playPass(from: 104)
        #expect(player.passSettings?.tempo == 64)
    }

    @Test func aHintReachesThePass() {
        var player = playing()
        player.handle(.hint(isShown: true, at: s(101)))
        player.handle(.hint(isShown: false, at: s(102)))
        player.playPass(from: 104)
        #expect(player.summary.blocks[0].passes?.cleanPasses == 0)
        #expect(player.summary.blocks[0].passes?.passes == 1)
    }
}

@Suite("Scales in a session: summary")
struct SessionPassSummaryTests {
    @Test func passesCleanFastestTempoAndEvenness() throws {
        var setup = themed()
        setup.options.pass.holdsTempo = false
        var player = playing(setup: setup)
        // Clean at 60, then at 64 with a hint, then cut short.
        let end = player.playPass(from: 104)
        player.tick(end + 6)
        player.handle(.hint(isShown: true, at: s(end + 6)))
        player.handle(.hint(isShown: false, at: s(end + 6.1)))
        let second = player.playPass(from: player.drill!.promptStart! / .seconds(1))
        player.tick(second + 6)
        player.skip(to: second + 6.1)
        player.handle(.end(at: s(second + 7)))
        let summary = player.summary
        let passes = try #require(summary.blocks[0].passes)
        #expect(passes.passes == 2)
        #expect(passes.cleanPasses == 1)
        #expect(passes.fastestCleanTempo == 60)
        #expect(passes.medianEvenness.map { $0 < .milliseconds(20) } == true)
        #expect(passes.cleanText == "1 of 2")
        #expect(passes.tempoText == "clean at 60 BPM")
        #expect(passes.detailText.hasPrefix("2 passes · 1 clean\nevenness "))
        #expect(summary.slowest(3).isEmpty)
        #expect(!summary.hasNoAttempts)
    }

    @Test func withoutPasses() {
        var player = playing()
        player.handle(.end(at: s(101)))
        let passes = player.summary.blocks[0].passes
        #expect(passes?.cleanText == "–")
        #expect(passes?.tempoText == nil)
        #expect(passes?.detailText == "0 passes · 0 clean")
    }

    @Test func otherBlocksHaveNone() {
        var player = playing([.notePlayIt])
        player.handle(.end(at: s(101)))
        #expect(player.summary.blocks[0].passes == nil)
    }
}
