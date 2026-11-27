import Testing
import PracticeCore
import TheoryCore

/// I–V–vi–IV in G, in the E shape, at 60 BPM, as in `ProgressionRun`: the count-in is 0–4 s, then G 4–8, D 8–12,
/// Em 12–16 and C 16–20.
@Suite("Free time")
struct FreeTimeTests {
    @Test func loopsTheThemesBackingUntilStopped() throws {
        var run = ProgressionRun(.freeTime)
        run.start()
        let requests = run.drill.takeBacking()
        guard case .start(let backing) = try #require(requests.first) else { Issue.record("no backing"); return }
        #expect(requests.count == 1)
        #expect(backing.chords.map(\.triad) == run.chords)
        #expect(backing.bpm == 60)
        #expect(backing.start == s(0))
        run.tick(600)
        #expect(run.drill.isRunning)
        #expect(run.drill.takeBacking().isEmpty)
        run.drill.handle(.stop(at: s(601)))
        #expect(run.drill.takeBacking() == [.stop])
        #expect(!run.drill.isRunning)
    }

    @Test func asksNothingAndLogsNothing() {
        var run = ProgressionRun(.freeTime)
        run.start()
        run.play(0, [4, 3, 3])
        run.drill.handle(.skip(at: s(7)))
        run.tick(30)
        #expect(run.drill.attempts.isEmpty)
        #expect(run.drill.prompt == nil)
        #expect(!run.drill.kind.fades)
    }

    @Test func showsTheThemesPositionAndTheChordThatSounds() throws {
        var run = ProgressionRun(.freeTime)
        run.start()
        run.tick(2)
        #expect(run.drill.display?.headline == "Free time")
        run.tick(9)
        let display = try #require(run.drill.display)
        #expect(display.headline == "D")
        #expect(display.subline == "I–V–vi–IV in G · E shape")
        #expect(Set(display.markers.map(\.location)) == Set(run.position.locations))
        #expect(display.markers.filter(\.isAnswer).allSatisfy { run.fretboard.pitch(at: $0.location).pitchClass == NoteName.g.pitchClass })
        #expect(display.markers.allSatisfy { $0.opacity == 1 })
        run.tick(16 + 16 + 1)
        #expect(run.drill.display?.headline == "C")
    }

    @Test func pausingStopsTheBackingAndResumeCountsInAgain() throws {
        var run = ProgressionRun(.freeTime)
        run.start()
        _ = run.drill.takeBacking()
        run.drill.handle(.pause(at: s(10)))
        #expect(run.drill.takeBacking() == [.stop])
        #expect(run.drill.display == nil)
        run.drill.handle(.resume(at: s(30)))
        guard case .start(let backing) = try #require(run.drill.takeBacking().first) else {
            Issue.record("no backing"); return
        }
        #expect(backing.start == s(30))
    }

    @Test func needsSound() {
        #expect(DrillKind.freeTime.needsSound)
        #expect(DrillKind.freeTime.hasBacking)
        #expect(DrillKind.freeTime.module == .progressions)
        #expect(DrillKind.all.suffix(2).map(\.id) == ["chordsInPosition", "freeTime"])
    }

    @Test func aSessionWithoutSoundLeavesItOutWithTheUsualNotice() {
        let setup = ProgressionRun(.freeTime).drill.setup
        let kinds: [DrillKind] = [.chordsInPosition, .stayInPosition, .freeTime]
        #expect(SessionPlanner.drills(from: kinds, for: setup, hasSound: false).map(\.id) == ["chordsInPosition", "stayInPosition"])
        #expect(SessionPlanner.drills(from: kinds, for: setup, hasSound: true).count == 3)
        #expect(SessionPlanner.noSoundNotice(from: kinds) == "No sound: Free time is left out, and chimes flash.")
    }
}
