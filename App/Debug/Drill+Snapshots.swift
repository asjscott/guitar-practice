#if DEBUG
import PracticeCore
import TheoryCore

extension Drill {
    /// Where the prompt that is up can be answered (see `Snapshots`); nil with no prompt.
    var rightLocationForSnapshot: FretboardLocation? {
        guard let prompt else { return nil }
        let voicing = (self as? PromptDrill<TriadPlayItRules>)?.correctLocations ?? []
        return prompt.target ?? voicing.first { $0.string == prompt.string }
            ?? fretboard.locations(of: prompt.pitchClass, onString: prompt.string, frets: options.frets).first
    }
}

/// A progression drill's drawn path, in time with the backing as heard (see `Snapshots`): `count` chords whole, those
/// in `wrong` as a wrong pitch, then `partial` notes of the next.
func progressionNotesForSnapshot(_ progression: Progression, in key: Key, position: Position, on fretboard: Fretboard,
                                 backing: Backing, chords count: Int, wrong: Set<Int> = [],
                                 partial: Int = 0) -> [(pitch: Pitch, onset: Duration)] {
    let chords = progression.chords(in: key)
    let bars = progression.steps.map(\.bars)
    let beatLength = Duration.seconds(60) / backing.bpm
    var notes: [(pitch: Pitch, onset: Duration)] = []
    var previous: TriadVoicing?
    var slotBeat = Double(Backing.beatsPerBar)
    for slot in 0..<(count + (partial > 0 ? 1 : 0)) {
        let index = slot % chords.count
        let voicing = previous.flatMap { fretboard.nearestVoicings(of: chords[index], in: position, to: $0).first }
            ?? fretboard.middleVoicing(of: chords[index], in: position)!
        let pitches = voicing.locations.map(fretboard.pitch)
        let start = backing.start + beatLength * slotBeat
        if wrong.contains(slot) {
            notes.append((pitches[0] + Interval(1), start))
            previous = nil
        } else {
            for (offset, pitch) in pitches.prefix(slot < count ? 3 : partial).enumerated() {
                notes.append((pitch, start + beatLength * (0.5 * Double(offset))))
            }
            previous = voicing
        }
        slotBeat += Double(bars[index] * Backing.beatsPerBar)
    }
    return notes
}

extension DrillViewModel {
    /// Plays a progression drill's drawn path in time with the backing as heard (see `progressionNotesForSnapshot`);
    /// then moves the clock to `beat`, counted from the count-in's first.
    func playProgressionForSnapshot(chords count: Int, wrong: Set<Int> = [], partial: Int = 0, untilBeat beat: Double) {
        guard let backing = backingForSnapshot, let position = progressionPosition else { return }
        let notes = progressionNotesForSnapshot(progression, in: options.key, position: position, on: fretboard,
                                                backing: backing, chords: count, wrong: wrong, partial: partial)
        playForSnapshot(notes, until: backing.start + Duration.seconds(60) / backing.bpm * beat)
    }
}
#endif
