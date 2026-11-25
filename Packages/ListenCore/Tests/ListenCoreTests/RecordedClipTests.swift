import Testing
import ListenCore

/// Self-recorded clips of a real guitar through the interface. Attack times
/// were measured from the waveform (the 5 ms peak level), not by ListenCore.
@Suite("Recorded clips")
struct RecordedClipTests {
    /// A real pick attack builds up over tens of milliseconds, unlike a synthetic pluck.
    static let onsetTolerance = 0.05

    @Test("One pluck gives one played note", arguments: [
        ("low-e-open", 40, 0.065),
        ("drop-d-low-d", 38, 0.634),
        ("low-e-12-fret", 52, 0.09),
        ("high-e-fret-22", 86, 0.334),
    ])
    func onePluck(name: String, midi: Int, attack: Double) throws {
        let clip = try Clip(name)
        let notes = playedNotes(clip.samples, sampleRate: clip.sampleRate)
        #expect(notes.map(\.midiNote) == [midi])
        let first = try #require(notes.first)
        #expect(abs(first.onset - attack) <= Self.onsetTolerance)
    }

    @Test("Low strings are reported within 150 ms of the attack", arguments: [("low-e-open", 40, 0.065), ("drop-d-low-d", 38, 0.634)])
    func latency(name: String, midi: Int, attack: Double) throws {
        let clip = try Clip(name)
        let first = try #require(reportedNotes(clip.samples, sampleRate: clip.sampleRate).first)
        #expect(first.note.midiNote == midi)
        #expect(first.reportedAt - attack <= 0.15)
    }

    @Test func fourPlucksOfOneNoteAreFourPlayedNotes() throws {
        let clip = try Clip("A-string-4-plucks")
        let notes = playedNotes(clip.samples, sampleRate: clip.sampleRate)
        #expect(notes.map(\.midiNote) == [45, 45, 45, 45])
        for (note, attack) in zip(notes, [0.095, 1.242, 2.295, 3.183]) {
            #expect(abs(note.onset - attack) <= Self.onsetTolerance)
        }
    }

    @Test func aPluggedInGuitarNotBeingPlayedIsSilence() throws {
        let clip = try Clip("silence")
        #expect(clip.samples.count > 2 * Int(clip.sampleRate))
        #expect(playedNotes(clip.samples, sampleRate: clip.sampleRate).isEmpty)
        #expect(tunerReadings(clip.samples, from: 0, to: 10, sampleRate: clip.sampleRate).allSatisfy { $0 == nil })
    }

    @Test("The tuner never reads the wrong octave", arguments: [
        ("low-e-open", 40, 0.065), ("drop-d-low-d", 38, 0.634), ("low-e-12-fret", 52, 0.09), ("high-e-fret-22", 86, 0.334),
    ])
    func tunerOctave(name: String, midi: Int, attack: Double) throws {
        let clip = try Clip(name)
        let readings = tunerReadings(clip.samples, from: attack + 0.15, to: 10, sampleRate: clip.sampleRate).compactMap { $0 }
        #expect(!readings.isEmpty)
        #expect(Set(readings.map(\.midiNote)) == [midi])
    }

    /// Hammer-ons and pull-offs between D3 and E3. Only the four places where the
    /// level jumps start a played note; a pitch change alone doesn't (spec #11).
    @Test func legatoGivesAPlayedNoteOnlyWhereTheLevelJumps() throws {
        let clip = try Clip("a-string-legato")
        let notes = playedNotes(clip.samples, sampleRate: clip.sampleRate)
        #expect(notes.map(\.midiNote) == [50, 52, 50, 52])
        for (note, jump) in zip(notes, [0.224, 1.497, 1.641, 2.295]) {
            #expect(abs(note.onset - jump) <= Self.onsetTolerance)
        }
    }

    /// C major, CAGED E shape (B2 to D5 and back), one note per click at 120 BPM with the click in headphones, every note
    /// picked: each is heard once, at the right pitch. The top note is in both clips.
    @Test("A picked scale is heard note by note", arguments: [
        ("scale-up", [47, 48, 50, 52, 53, 55, 57, 59, 60, 62, 64, 65, 67, 69, 71, 72, 74],
         [0.49, 1.05, 1.52, 2.0, 2.49, 3.0, 3.51, 3.995, 4.5, 5.01, 5.5,
          5.995, 6.505, 6.98, 7.495, 8.0, 8.495]),
        ("scale-down", [74, 72, 71, 69, 67, 65, 64, 62, 60, 59, 57, 55, 53, 52, 50, 48, 47],
         [0.065, 0.6, 1.065, 1.555, 2.07, 2.575, 3.075, 3.57, 4.075, 4.58,
          5.075, 5.58, 6.085, 6.565, 7.075, 7.58, 8.075]),
    ])
    func scale(name: String, midi: [Int], attacks: [Double]) throws {
        let clip = try Clip(name)
        let notes = playedNotes(clip.samples, sampleRate: clip.sampleRate)
        #expect(notes.map(\.midiNote) == midi)
        for (note, attack) in zip(notes, attacks) {
            #expect(abs(note.onset - attack) <= Self.onsetTolerance, "\(note.midiNote) at \(note.onset), not \(attack)")
        }
    }
}
