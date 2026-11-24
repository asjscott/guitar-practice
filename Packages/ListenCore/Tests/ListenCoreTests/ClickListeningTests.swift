import Foundation
import Testing
import ListenCore

/// Clicks reach the listener only through a microphone; an interface doesn't hear them. Levels are the click's peak
/// against the note's, in dB. Where the listener can't cope yet, the test stays as strict and is a known issue.
@Suite("Listening through clicks")
struct ClickListeningTests {
    static let onsetTolerance = 0.005
    /// Clicks well below the guitar, as from headphones near the microphone.
    static let faint = -30.0

    /// Adds clicks at a steady tempo, every fourth one emphasised, each scaled so that its peak is `peak`.
    static func addClicks(
        to samples: [Float], bpm: Double, from start: Double, peak: Double, sampleRate: Double = Signals.sampleRate
    ) -> [Float] {
        let clicks = [true, false].map { emphasised -> [Float] in
            let click = Click.samples(emphasised: emphasised, sampleRate: sampleRate)
            let loudest = click.map(abs).max() ?? 1
            return click.map { $0 * Float(peak) / loudest }
        }
        var result = samples
        var count = 0
        while true {
            let offset = Int((start + Double(count) * 60 / bpm) * sampleRate)
            guard offset < result.count else { return result }
            for (index, sample) in clicks[count % 4 == 0 ? 0 : 1].enumerated() where offset + index < result.count {
                result[offset + index] += sample
            }
            count += 1
        }
    }

    // MARK: Clicks alone

    @Test("Clicks alone give no played note", arguments: [40.0, 60, 100, 160], [0.0, -3, -12, -24, -40])
    func alone(bpm: Double, dBFS: Double) {
        let samples = Self.addClicks(to: Signals.silence(3), bpm: bpm, from: 0.1, peak: Signals.amplitude(dBFS: dBFS))
        #expect(playedNotes(samples).isEmpty)
    }

    @Test("Clicks alone, at other sample rates", arguments: [44_100.0, 96_000])
    func alone(sampleRate: Double) {
        let silence = Signals.silence(3, sampleRate: sampleRate)
        #expect(playedNotes(Self.addClicks(to: silence, bpm: 160, from: 0.1, peak: 1, sampleRate: sampleRate), sampleRate: sampleRate).isEmpty)
    }

    // MARK: Clicks over ringing notes

    /// A note ringing for a second, with clicks from `delay` after it is plucked.
    func notesHeard(midi: Int, peak: Double, clicks level: Double, delay: Double) -> [PlayedNote] {
        let note = Signals.silence(0.2) + Signals.pluck(frequency: Signals.hz(midi: midi), peak: peak, duration: 1)
        return playedNotes(Self.addClicks(to: note, bpm: 120, from: 0.2 + delay, peak: peak * Signals.amplitude(dBFS: level)))
    }

    func expectOne(_ notes: [PlayedNote], midi: Int, onsetTolerance: Double = onsetTolerance) {
        #expect(notes.map(\.midiNote) == [midi])
        #expect(notes.allSatisfy { abs($0.cents) <= 5 })
        #expect(notes.allSatisfy { abs($0.onset - 0.2) <= onsetTolerance })
    }

    /// Loud and soft are peaks of 0.5 and 0.05 (with harmonics, about −14 and −34 dBFS RMS).
    @Test("Faint clicks don't split, hide or retune a ringing note", arguments: [40, 45, 64, 76], [0.5, 0.05])
    func faintClicks(midi: Int, peak: Double) {
        for delay in [0, 0.03, 0.06, 0.1, 0.3] {
            expectOne(notesHeard(midi: midi, peak: peak, clicks: Self.faint, delay: delay), midi: midi)
        }
    }

    /// A jump of 3 dB is an onset, and a click as loud as the note makes one, so the note is reported again.
    @Test("Clicks as loud as a ringing note don't split it", arguments: [40, 45, 64, 76], [0.5, 0.05])
    func loudClicks(midi: Int, peak: Double) {
        withKnownIssue("Clicks split ringing notes: #34") {
            expectOne(notesHeard(midi: midi, peak: peak, clicks: 0, delay: 0.3), midi: midi)
        }
    }

    @Test("Faint clicks don't change what is heard in a recorded clip", arguments: [
        ("low-e-open", [40]), ("low-e-12-fret", [52]), ("A-string-4-plucks", [45, 45, 45, 45]),
    ])
    func faintClicks(name: String, midi: [Int]) throws {
        #expect(try notesHeard(in: name, clicks: Self.faint) == midi)
    }

    @Test("Clicks 6 dB below the guitar don't split recorded notes", arguments: [
        ("low-e-open", [40]), ("low-e-12-fret", [52]), ("A-string-4-plucks", [45, 45, 45, 45]), ("high-e-fret-22", [86]),
    ])
    func loudClicks(name: String, midi: [Int]) throws {
        let heard = try notesHeard(in: name, clicks: -6)
        withKnownIssue("Clicks split ringing notes: #34") {
            #expect(heard == midi)
        }
    }

    func notesHeard(in name: String, clicks level: Double) throws -> [Int] {
        let clip = try Clip(name)
        let peak = Double(clip.samples.map(abs).max() ?? 0) * Signals.amplitude(dBFS: level)
        let samples = Self.addClicks(to: clip.samples, bpm: 120, from: 0, peak: peak, sampleRate: clip.sampleRate)
        return playedNotes(samples, sampleRate: clip.sampleRate).map(\.midiNote)
    }

    // MARK: Runs

    static let lowRun = [40, 42, 43, 45, 47, 48, 50, 52]
    static let highRun = [64, 66, 67, 69, 71, 72, 74, 76]

    /// One note per beat, each stopped by the next, as on one string; first at 0.3 s. Each note has died away by
    /// more than 3 dB when the next is plucked, even at 160 BPM.
    func run(_ midi: [Int], bpm: Double, decay: Double = 0.6) -> [Float] {
        Signals.silence(0.3) + midi.flatMap { Signals.pluck(frequency: Signals.hz(midi: $0), decay: decay, duration: 60 / bpm) }
    }

    func expectRun(_ notes: [PlayedNote], _ midi: [Int], bpm: Double) {
        #expect(notes.map(\.midiNote) == midi)
        for (index, note) in notes.enumerated() {
            #expect(abs(note.onset - (0.3 + Double(index) * 60 / bpm)) <= Self.onsetTolerance)
        }
    }

    @Test("Every note of a run is heard once", arguments: [60.0, 120, 160], [lowRun, highRun])
    func runs(bpm: Double, midi: [Int]) {
        expectRun(playedNotes(run(midi, bpm: bpm)), midi, bpm: bpm)
    }

    @Test("Every note of a run is heard once through faint clicks", arguments: [60.0, 120, 160], [lowRun, highRun])
    func runsWithFaintClicks(bpm: Double, midi: [Int]) {
        for delay in [0, 0.03] {
            let samples = Self.addClicks(to: run(midi, bpm: bpm), bpm: bpm, from: 0.3 + delay, peak: 0.5 * Signals.amplitude(dBFS: Self.faint))
            expectRun(playedNotes(samples), midi, bpm: bpm)
        }
    }

    /// 100 ms late, as from a wireless speaker: the note's report is put off, and its onset is the click's.
    @Test("Every note of a run is heard once through clicks as loud", arguments: [60.0, 120, 160], [lowRun, highRun])
    func runsWithLoudClicks(bpm: Double, midi: [Int]) {
        withKnownIssue("Clicks move onsets and split notes: #34") {
            expectRun(playedNotes(Self.addClicks(to: run(midi, bpm: bpm), bpm: bpm, from: 0.4, peak: 0.5)), midi, bpm: bpm)
        }
    }

    /// No clicks: the onset detector needs a 3 dB jump, which a pluck over a note ringing nearly as loud isn't.
    @Test("Every note of a long-ringing run is heard at 160 BPM", arguments: [lowRun, highRun])
    func longRingingRun(midi: [Int]) {
        withKnownIssue("A pluck less than 3 dB over the ringing note is missed: #34") {
            expectRun(playedNotes(run(midi, bpm: 160, decay: 1.2)), midi, bpm: 160)
        }
    }
}
