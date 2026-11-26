import Testing
import ListenCore

/// Self-recorded triads arpeggiated low to high on beats 1–3 at 70 BPM (one take at 100), each note left ringing under
/// the next, with the click in headphones only (ticket #52). Each take is cut into overlapping clips so that every chord
/// change is in one. Attack times were measured from the waveform (the 5 ms peak level), not by ListenCore.
@Suite("Ringing arpeggios")
struct ArpeggioClipTests {
    struct Arpeggio: Sendable, CustomTestStringConvertible {
        let name: String
        let chords: [[Int]]
        let attacks: [Double]
        var testDescription: String { name }
    }

    // G, D, Em and C in G major, CAGED E shape.
    static let topSet: [[Int]] = [[59, 62, 67], [57, 62, 66], [59, 64, 67], [60, 64, 67]]       // strings 3–1
    static let middleSet: [[Int]] = [[55, 59, 62], [54, 57, 62], [55, 59, 64], [55, 60, 64]]    // strings 4–2
    // Em, C, D and Em: G has no voicing on strings 6–4 in this position.
    static let lowSet: [[Int]] = [[43, 47, 52], [43, 48, 52], [45, 50, 54], [43, 47, 52]]       // strings 6–4

    static let clips: [Arpeggio] = [
        Arpeggio(name: "triads-gbe-a", chords: Array(topSet[0...2]),
                 attacks: [1.017, 1.845, 2.673, 4.459, 5.272, 6.075, 7.841, 8.659, 9.472]),
        Arpeggio(name: "triads-gbe-b", chords: Array(topSet[2...3]),
                 attacks: [0.291, 1.109, 1.922, 3.728, 4.536, 5.394]),
        Arpeggio(name: "triads-gbe-100", chords: topSet,
                 attacks: [1.024, 1.578, 2.121, 3.383, 3.962, 4.551, 5.768, 6.362, 6.940, 8.158, 8.736, 9.290]),
        Arpeggio(name: "triads-dgb-a", chords: Array(middleSet[0...2]),
                 attacks: [1.037, 1.810, 2.618, 4.439, 5.242, 6.060, 7.836, 8.629, 9.482]),
        Arpeggio(name: "triads-dgb-b", chords: Array(middleSet[2...3]),
                 attacks: [0.286, 1.079, 1.932, 3.743, 4.661, 5.444]),
        Arpeggio(name: "triads-ead-a", chords: Array(lowSet[0...2]),
                 attacks: [1.022, 1.855, 2.683, 4.439, 5.287, 6.090, 7.861, 8.639, 9.433]),
        Arpeggio(name: "triads-ead-b", chords: Array(lowSet[2...3]),
                 attacks: [0.161, 0.939, 1.733, 3.613, 4.436, 5.250]),
    ]

    @Test("Every note of a ringing arpeggio is heard once", arguments: clips)
    func arpeggio(_ arpeggio: Arpeggio) throws {
        let clip = try Clip(arpeggio.name)
        let notes = playedNotes(clip.samples, sampleRate: clip.sampleRate)
        let heard = notes.map { "\($0.midiNote)@\(($0.onset * 1000).rounded() / 1000)" }.joined(separator: " ")
        #expect(notes.map(\.midiNote) == Array(arpeggio.chords.joined()), "heard \(heard)")
        for (note, attack) in zip(notes, arpeggio.attacks) {
            #expect(abs(note.onset - attack) <= RecordedClipTests.onsetTolerance, "\(note.midiNote) at \(note.onset), not \(attack)")
        }
    }

    /// Through an interface the clicks aren't heard; through a microphone faint ones may be.
    @Test("Faint clicks don't change what is heard in a ringing arpeggio", arguments: clips)
    func arpeggioWithClicks(_ arpeggio: Arpeggio) throws {
        let clip = try Clip(arpeggio.name)
        let peak = Double(clip.samples.map(abs).max() ?? 0) * Signals.amplitude(dBFS: -24)
        let bpm = arpeggio.name.hasSuffix("-100") ? 100.0 : 70
        let samples = ClickListeningTests.addClicks(
            to: clip.samples, bpm: bpm, from: arpeggio.attacks[0], peak: peak, sampleRate: clip.sampleRate
        )
        #expect(playedNotes(samples, sampleRate: clip.sampleRate).map(\.midiNote) == Array(arpeggio.chords.joined()))
    }
}
