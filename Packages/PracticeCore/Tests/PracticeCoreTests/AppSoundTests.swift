import Testing
import TheoryCore
import PracticeCore

private let tones = AppSound.tones([
    DrillTone(pitch: Pitch(40), duration: .milliseconds(600)),
    DrillTone(pitch: Pitch(45), duration: .milliseconds(600)),
])

@Suite("App sound")
struct AppSoundTests {
    @Test func tonesPlayOneAfterAnother() {
        #expect(tones.duration == s(1.2))
    }

    @Test func notesStartingDuringASoundOrWithin300MsAfterItAreIgnored() {
        var filter = AppSoundFilter()
        #expect(!filter.ignores(onset: s(10)))
        filter.started(tones, at: s(10), latency: .zero)
        #expect(!filter.ignores(onset: s(9.999)))
        #expect(filter.ignores(onset: s(10)))
        #expect(filter.ignores(onset: s(11.2)))
        #expect(filter.ignores(onset: s(11.5)))
        #expect(!filter.ignores(onset: s(11.501)))
    }

    @Test func aLateOutputIsIgnoredUntilItHasReallyEnded() {
        var filter = AppSoundFilter()
        filter.started(tones, at: s(10), latency: s(0.2))
        #expect(filter.ignores(onset: s(10)))
        #expect(filter.ignores(onset: s(11.7)))
        #expect(!filter.ignores(onset: s(11.701)))
    }

    @Test func stoppingTonesEndsThemEarlyButNotAChime() {
        var filter = AppSoundFilter()
        filter.started(tones, at: s(10), latency: s(0.1))
        filter.tonesStopped(at: s(10.2))
        #expect(filter.ignores(onset: s(10.6)))       // 10.2 + 0.1 latency + 0.3
        #expect(!filter.ignores(onset: s(10.601)))

        filter.started(.chime, at: s(20), latency: .zero)
        filter.tonesStopped(at: s(20.1))
        #expect(filter.ignores(onset: s(20) + AppSound.chime.duration))
    }

    @Test func stoppingAfterTheTonesEndedChangesNothing() {
        var filter = AppSoundFilter()
        filter.started(tones, at: s(10), latency: .zero)
        filter.tonesStopped(at: s(20))
        #expect(!filter.ignores(onset: s(11.6)))
    }

    @Test func earlierSoundsStillCountForNotesDetectedLate() {
        var filter = AppSoundFilter()
        filter.started(tones, at: s(10), latency: .zero)
        filter.started(tones, at: s(15), latency: .zero)
        #expect(filter.ignores(onset: s(10.5)))
        #expect(!filter.ignores(onset: s(13)))
        #expect(filter.ignores(onset: s(16)))
    }
}
