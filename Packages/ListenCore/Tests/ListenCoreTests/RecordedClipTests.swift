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
}
