import Testing
import PracticeCore

/// At 80 BPM a click is 0.75 s. Asked to start at 0, the count-in's four clicks are at 0–2.25 s and the eight to play
/// on at 3, 3.75, … 8.25 s.
private let playedOn = (0..<8).map { 3 + 0.75 * Double($0) }

/// A check started at 0, its clicks heard as asked, with a note played on each click at these offsets in ms (nil:
/// none).
private func check(offsets: [Double?], start: Double = 0) -> LatencyCheck {
    var check = LatencyCheck(start: s(start))
    for (click, offset) in zip(playedOn, offsets) {
        if let offset { check.heard(onset: s(start + click + offset / 1000)) }
    }
    return check
}

@Suite("Latency check")
struct LatencyCheckTests {
    @Test func aBarOfCountInThenEightClicksAt80BPM() {
        let check = LatencyCheck(start: s(1))
        #expect(check.track.bpm == 80)
        #expect(check.track.start == s(1))
        #expect(check.clickTimes == playedOn.map { s(1 + $0) })
        // Listening ends half a beat after the last click.
        #expect(check.end == s(1 + 8.25 + 0.375))
    }

    @Test func theInputDelayIsTheMedianOffsetOfTheOnsetsFromTheClicks() {
        // 15 18 19 20 20 21 22 25: the middle two are 20.
        let check = check(offsets: [18, 22, 20, 25, 15, 20, 21, 19])
        #expect(check.result == .measured(.milliseconds(20)))
    }

    @Test func sixHeardIsEnough() {
        // 10 20 30 40 50 60: the middle two make 35.
        let check = check(offsets: [30, nil, 10, 20, nil, 40, 50, 60])
        #expect(check.result == .measured(.milliseconds(35)))
    }

    @Test func fewerThanSixHeardIsTryAgain() {
        let check = check(offsets: [30, nil, 10, 20, nil, 40, nil, 60])
        #expect(check.result == .tooFew(heard: 5))
        #expect(LatencyCheck(start: .zero).result == .tooFew(heard: 0))
    }

    @Test func eachClickTakesItsNearestOnsetWithinHalfABeat() {
        var check = check(offsets: [40, 40, 40, 40, 40, 40, nil, nil])
        // A second note after a click, one in the count-in, and one more than half a beat after the last click.
        check.heard(onset: s(3 + 0.3))
        check.heard(onset: s(1.5))
        check.heard(onset: s(8.25 + 0.4))
        #expect(check.result == .measured(.milliseconds(40)))
    }

    @Test func playingAheadOfTheClicksMeasuresNoDelay() {
        let check = check(offsets: [-30, -20, -40, -25, -30, -35, -20, -30])
        #expect(check.result == .measured(.zero))
    }

    @Test func theClicksAreTakenAsHeard() {
        var check = LatencyCheck(start: .zero)
        let heard = ClickTrack(meter: check.track.meter, bpm: 80, start: s(0.5))
        check.clicksStarted(heard)
        for click in playedOn { check.heard(onset: s(0.5 + click + 0.012)) }
        #expect(check.clickTimes.first == s(3.5))
        #expect(check.result == .measured(.milliseconds(12)))
    }

    @Test func itShowsTheCountInThenWhichClick() {
        let check = LatencyCheck(start: .zero)
        #expect(check.progress(at: s(-0.1)) == nil)
        #expect(check.progress(at: s(0.8)) == .countIn(2))
        #expect(check.progress(at: s(3.1)) == .click(1))
        #expect(check.progress(at: s(8.3)) == .click(8))
        #expect(check.progress(at: s(8.7)) == nil)
    }
}
