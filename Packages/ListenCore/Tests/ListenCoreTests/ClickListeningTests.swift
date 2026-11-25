import Foundation
import Testing
import ListenCore

/// Clicks reach the listener only through a microphone; an interface doesn't hear them. Levels are the click's peak
/// against the note's, in dB. The onset rule and its limits are in ADR 0005.
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

    @Test("Clicks as loud as a ringing note don't split it", arguments: [40, 45, 64, 76], [0.5, 0.05])
    func loudClicks(midi: Int, peak: Double) {
        for delay in [0.06, 0.3] {
            for level in [-12.0, 0] {
                expectOne(notesHeard(midi: midi, peak: peak, clicks: level, delay: delay), midi: midi)
            }
        }
    }

    @Test("Faint clicks don't change what is heard in a recorded clip", arguments: [
        ("low-e-open", [40]), ("low-e-12-fret", [52]), ("A-string-4-plucks", [45, 45, 45, 45]),
    ])
    func faintClicks(name: String, midi: [Int]) throws {
        #expect(try notesHeard(in: name, clicks: Self.faint) == midi)
    }

    /// The A string's clip is left to the faint test: a click as a finger stops the string can make an extra note.
    @Test("Clicks as loud as the guitar don't split recorded notes", arguments: [
        ("low-e-open", [40]), ("drop-d-low-d", [38]), ("low-e-12-fret", [52]), ("high-e-fret-22", [86]),
    ], [-24.0, 0])
    func loudClicks(clip: (name: String, midi: [Int]), level: Double) throws {
        for start in [0.17, 0.34] {
            #expect(try notesHeard(in: clip.name, clicks: level, from: start) == clip.midi)
        }
    }

    func notesHeard(in name: String, clicks level: Double, from start: Double = 0) throws -> [Int] {
        let clip = try Clip(name)
        let peak = Double(clip.samples.map(abs).max() ?? 0) * Signals.amplitude(dBFS: level)
        let samples = Self.addClicks(to: clip.samples, bpm: 120, from: start, peak: peak, sampleRate: clip.sampleRate)
        return playedNotes(samples, sampleRate: clip.sampleRate).map(\.midiNote)
    }

    // MARK: Lines

    static let lowLine = [40, 42, 43, 45, 47, 48, 50, 52]
    static let highLine = [64, 66, 67, 69, 71, 72, 74, 76]

    /// One note per beat, each stopped by the next, as on one string; first at 0.3 s. Each note has died away by
    /// more than 3 dB when the next is plucked, even at 160 BPM.
    func line(_ midi: [Int], bpm: Double, decay: Double = 0.6) -> [Float] {
        Signals.silence(0.3) + midi.flatMap { Signals.pluck(frequency: Signals.hz(midi: $0), decay: decay, duration: 60 / bpm) }
    }

    func expectLine(_ notes: [PlayedNote], _ midi: [Int], bpm: Double) {
        #expect(notes.map(\.midiNote) == midi)
        for (index, note) in notes.enumerated() {
            #expect(abs(note.onset - (0.3 + Double(index) * 60 / bpm)) <= Self.onsetTolerance)
        }
    }

    @Test("Every note of a line is heard once", arguments: [60.0, 120, 160], [lowLine, highLine])
    func lines(bpm: Double, midi: [Int]) {
        expectLine(playedNotes(line(midi, bpm: bpm)), midi, bpm: bpm)
    }

    @Test("Every note of a line is heard once through faint clicks", arguments: [60.0, 120, 160], [lowLine, highLine])
    func linesWithFaintClicks(bpm: Double, midi: [Int]) {
        for delay in [0, 0.03] {
            let samples = Self.addClicks(to: line(midi, bpm: bpm), bpm: bpm, from: 0.3 + delay, peak: 0.5 * Signals.amplitude(dBFS: Self.faint))
            expectLine(playedNotes(samples), midi, bpm: bpm)
        }
    }

    @Test("Every note of a line is heard once through clicks as loud, 100 ms late", arguments: [60.0, 120, 160], [lowLine, highLine])
    func linesWithLoudClicks(bpm: Double, midi: [Int]) {
        expectLine(playedNotes(Self.addClicks(to: line(midi, bpm: bpm), bpm: bpm, from: 0.4, peak: 0.5)), midi, bpm: bpm)
    }

    @Test("Every note of a long-ringing line is heard at 160 BPM", arguments: [lowLine, highLine])
    func longRingingLine(midi: [Int]) {
        // Each pluck is only 2.7 dB over the note before it.
        expectLine(playedNotes(line(midi, bpm: 160, decay: 1.2)), midi, bpm: 160)
    }

    // MARK: Picked lines

    /// One note per beat, each up to 30 ms early or late and 2 dB louder or softer, and up to 10 cents out of tune.
    func pickedLine(_ midi: [Int], bpm: Double, decay: Double, seed: UInt64) -> (samples: [Float], times: [Double]) {
        var random = Signals.Random(seed: seed)
        let times = midi.indices.map { 0.3 + Double($0) * 60 / bpm + random.next(-0.03...0.03) }
        var samples = Signals.silence(0.3 + Double(midi.count) * 60 / bpm)
        for (index, time) in times.enumerated() {
            let end = index + 1 < times.count ? times[index + 1] : Double(samples.count) / Signals.sampleRate
            let note = Signals.pick(frequency: Signals.hz(midi: midi[index], cents: random.next(-10...10)),
                                    peak: 0.4 * Signals.amplitude(dBFS: random.next(-2...2)), decay: decay,
                                    duration: end - time, random: &random)
            let offset = Int(time * Signals.sampleRate)
            for (sample, value) in note.enumerated() where offset + sample < samples.count { samples[offset + sample] += value }
        }
        return (samples, times)
    }

    /// Clicks are on the beat, so before some notes and after others. 10 ms is far inside the half beat that matters.
    @Test("Every note of a picked line is heard once, with clicks and without",
          arguments: [(90.0, 1.4), (120, 1.0), (160, 1.0)], [nil, -24.0, -12])
    func pickedLines(line: (bpm: Double, decay: Double), clicks: Double?) throws {
        for (seed, midi) in [Self.lowLine, [64, 66, 67, 69, 67, 66, 64]].enumerated() {
            let (dry, times) = pickedLine(midi, bpm: line.bpm, decay: line.decay, seed: UInt64(seed) + 1)
            let samples = clicks.map { Self.addClicks(to: dry, bpm: line.bpm, from: 0.3, peak: 0.4 * Signals.amplitude(dBFS: $0)) } ?? dry
            let notes = playedNotes(samples)
            #expect(notes.map(\.midiNote) == midi)
            for (note, time) in zip(notes, times) { #expect(abs(note.onset - time) <= 0.01) }
        }
    }

    @Test("One pitch picked again on the click is heard each time", arguments: [45, 57, 69], [nil, -24.0, -6])
    func samePitchAgain(midi: Int, clicks: Double?) {
        for seed in [UInt64(midi)] {
            let (dry, times) = pickedLine(Array(repeating: midi, count: 6), bpm: 120, decay: 0.8, seed: seed)
            let samples = clicks.map { Self.addClicks(to: dry, bpm: 120, from: 0.3, peak: 0.4 * Signals.amplitude(dBFS: $0)) } ?? dry
            let notes = playedNotes(samples)
            #expect(notes.map(\.midiNote) == Array(repeating: midi, count: 6))
            #expect(zip(notes, times).allSatisfy { abs($0.0.onset - $0.1) <= 0.06 })
        }
    }

    // MARK: Legato

    /// Between two pitches a tone apart, every 0.4 s, by a hammer-on or pull-off (4 ms) or a slide (60 ms), with
    /// the upper pitch softer, as loud or up to 2 dB louder.
    @Test("Legato is not a new played note", arguments: [0.004, 0.06], [-1.0, 0, 1, 2])
    func legato(glide: Double, louder: Double) {
        for midi in [45, 64] {
            var phase = 0.0
            let samples = (0..<Int(2.4 * Signals.sampleRate)).map { index -> Float in
                let time = Double(index) / Signals.sampleRate
                let step = Int(time / 0.4), into = time - Double(step) * 0.4
                func upper(after length: Double) -> Double {
                    let moved = min(1, into / length)
                    return step == 0 ? 0 : (step.isMultiple(of: 2) ? 1 - moved : moved)
                }
                phase += 2 * .pi * Signals.hz(midi: midi, cents: 200 * upper(after: glide)) / Signals.sampleRate
                let tone = (sin(phase) + 0.5 * sin(2 * phase) + 0.3 * sin(3 * phase)) / 1.8
                return Float(0.4 * exp(-time / 2) * Signals.amplitude(dBFS: louder * upper(after: 0.02)) * tone)
            }
            #expect(playedNotes(samples).map(\.midiNote) == [midi])
        }
    }
}
