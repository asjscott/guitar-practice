import PracticeCore
import Testing

private func signature(_ beats: Int, _ unit: Int) -> TimeSignature { TimeSignature(beats: beats, unit: unit)! }

@Suite("Time signatures and emphasis")
struct MeterTests {
    @Test func signaturesAre1To12Over4Or8() {
        #expect(TimeSignature.all.count == 24)
        #expect(TimeSignature(beats: 0, unit: 4) == nil)
        #expect(TimeSignature(beats: 13, unit: 8) == nil)
        #expect(TimeSignature(beats: 4, unit: 2) == nil)
        #expect(TimeSignature(beats: 12, unit: 8)?.name == "12/8")
    }

    @Test func eightCommonSignatures() {
        #expect(TimeSignature.common.map(\.name) == ["2/4", "3/4", "4/4", "5/4", "6/8", "7/8", "9/8", "12/8"])
    }

    @Test(arguments: TimeSignature.all)
    func aSignatureIsReadBackFromItsName(_ signature: TimeSignature) {
        #expect(TimeSignature(name: signature.name) == signature)
    }

    @Test(arguments: ["", "4", "4/", "4/4/4", "13/8", "3/2", "x/4"])
    func anythingElseIsNotASignature(_ name: String) {
        #expect(TimeSignature(name: name) == nil)
    }

    @Test func beat1IsEmphasisedAndTheGroupsInCompoundTime() {
        let groups: [String: Set<Int>] = ["6/8": [1, 4], "9/8": [1, 4, 7], "12/8": [1, 4, 7, 10]]
        for signature in TimeSignature.all {
            #expect(signature.usualEmphasis == groups[signature.name] ?? [1], "\(signature.name)")
        }
    }

    @Test func emphasisOffTheBarIsLeftOut() {
        #expect(Meter(signature(3, 4), emphasis: [0, 1, 3, 4]).emphasis == [1, 3])
        #expect(Meter(signature(3, 4), emphasis: []).emphasis == [])
        #expect(Meter(signature(6, 8)).emphasis == [1, 4])
    }

    /// Whole bars, at least four clicks, as few as that takes.
    @Test func countInClicksInEverySignature() {
        let clicks = [1: 4, 2: 4, 3: 6, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9, 10: 10, 11: 11, 12: 12]
        for signature in TimeSignature.all {
            #expect(signature.countInClicks == clicks[signature.beats], "\(signature.name)")
        }
    }
}

@Suite("Emphasis remembered per signature")
struct MeterMemoryTests {
    @Test func startsIn44WithBeat1() {
        #expect(MeterMemory().meter == Meter(signature(4, 4), emphasis: [1]))
    }

    @Test func eachSignatureKeepsItsOwn() {
        var memory = MeterMemory()
        memory.toggleEmphasis(ofBeat: 3)
        memory.signature = signature(6, 8)
        #expect(memory.meter.emphasis == [1, 4])
        memory.toggleEmphasis(ofBeat: 1)
        memory.toggleEmphasis(ofBeat: 4)
        #expect(memory.meter.emphasis == [])
        memory.signature = signature(4, 4)
        #expect(memory.meter.emphasis == [1, 3])
        memory.signature = signature(6, 8)
        #expect(memory.meter.emphasis == [])
    }

    @Test func survivesBeingStored() {
        var memory = MeterMemory()
        memory.toggleEmphasis(ofBeat: 3)
        memory.signature = signature(7, 8)
        memory.toggleEmphasis(ofBeat: 1)
        let read = MeterMemory(signature: memory.signature.name, emphasis: memory.storedEmphasis)
        #expect(read == memory)
        #expect(read.meter.emphasis == [])
    }

    @Test func whatCannotBeReadFallsBack() {
        let nonsense = MeterMemory(signature: "17/3", emphasis: "nonsense;4/4:x,3;9/9:1")
        #expect(nonsense.meter == Meter(signature(4, 4), emphasis: [3]))
        #expect(MeterMemory(signature: "3/4", emphasis: "4/4:1,3").meter == Meter(signature(3, 4)))
    }
}

@Suite("Clicks")
struct ClickScheduleTests {
    private let waltz = Meter(signature(3, 4), emphasis: [1, 2])

    private func track(_ bpm: Int = 60, at start: Duration = s(10)) -> ClickTrack {
        ClickTrack(meter: waltz, bpm: bpm, start: start)
    }

    @Test func bpmCountsClicksWhateverTheUnit() {
        let track = ClickTrack(meter: Meter(signature(6, 8)), bpm: 120, start: s(1))
        #expect(track.time(ofClick: 0) == s(1))
        #expect(track.time(ofClick: 3) == s(2.5))
    }

    @Test func clicksDoNotDrift() {
        #expect(track(70).time(ofClick: 70 * 60) == s(10 + 3600))
    }

    @Test func everyBeatClicks() {
        var schedule = ClickSchedule()
        schedule.start(track())
        let clicks = schedule.clicks(from: s(10), before: s(14))
        #expect(clicks.map(\.time) == [s(10), s(11), s(12), s(13)])
        #expect(clicks.map(\.beat) == [1, 2, 3, 1])
        #expect(clicks.map(\.isEmphasised) == [true, true, false, true])
        #expect(schedule.clicks(from: s(10.001), before: s(11)).isEmpty)
        #expect(schedule.clicks(from: s(5), before: s(10)).isEmpty)
    }

    /// Asked for a window at a time, every click comes once, at tempos that don't divide a minute evenly too.
    @Test(arguments: [40, 70, 113, 160])
    func eachClickComesOnceFromOneWindowToTheNext(_ bpm: Int) {
        var schedule = ClickSchedule()
        schedule.start(track(bpm))
        let edges = (0...60).map { track(bpm).time(ofClick: $0) }
        let clicks = zip(edges, edges.dropFirst()).flatMap { schedule.clicks(from: $0, before: $1) }
        #expect(clicks.map(\.time) == Array(edges.dropLast()))
        #expect(edges.dropLast().compactMap { schedule.current(at: $0) } == clicks)
    }

    @Test func theCurrentClickIsTheLastOneHeard() {
        var schedule = ClickSchedule()
        #expect(schedule.current(at: s(10)) == nil)
        schedule.start(track())
        #expect(schedule.current(at: s(9.99)) == nil)
        #expect(schedule.current(at: s(10))?.beat == 1)
        #expect(schedule.current(at: s(11.99))?.beat == 2)
        #expect(schedule.current(at: s(13))?.beat == 1)
    }

    @Test func stoppingAtATimeLeavesOutTheClickThen() {
        var schedule = ClickSchedule()
        schedule.start(track())
        schedule.stop(at: track().time(ofClick: 2))
        #expect(schedule.clicks(from: .zero, before: s(99)).map(\.time) == [s(10), s(11)])
        #expect(schedule.current(at: s(11.9))?.beat == 2)
        #expect(schedule.current(at: s(12)) == nil)
        #expect(!schedule.isOver(at: s(11.9)))
        #expect(schedule.isOver(at: s(12)))
    }

    @Test func aStopIsNotPutOff() {
        var schedule = ClickSchedule()
        schedule.start(track())
        schedule.stop(at: s(12))
        schedule.stop(at: s(20))
        #expect(schedule.isOver(at: s(12)))
    }

    @Test func oneTrackFollowsAnotherWithNoGap() {
        var schedule = ClickSchedule()
        schedule.start(track())
        schedule.start(track(120, at: s(13)))
        #expect(schedule.clicks(from: s(11), before: s(14)).map(\.time) == [s(11), s(12), s(13), s(13.5)])
        #expect(schedule.current(at: s(12.5))?.beat == 3)
        #expect(schedule.current(at: s(13))?.beat == 1)
    }

    @Test func aTrackReplacesOneThatHasNotStarted() {
        var schedule = ClickSchedule()
        schedule.start(track(at: s(20)))
        schedule.start(track(at: s(10)))
        #expect(schedule.clicks(from: .zero, before: s(12)).map(\.time) == [s(10), s(11)])
        schedule.stop(at: .zero)
        #expect(schedule.isOver(at: .zero))
        #expect(schedule.clicks(from: .zero, before: s(99)).isEmpty)
    }

    @Test func tracksThatAreOverAreForgotten() {
        var schedule = ClickSchedule()
        schedule.start(track())
        schedule.start(track(at: s(20)))
        schedule.forget(before: s(19.5))
        #expect(schedule.clicks(from: .zero, before: s(11)).count == 1)
        schedule.forget(before: s(20))
        #expect(schedule.clicks(from: .zero, before: s(22)).map(\.time) == [s(20), s(21)])
    }
}
