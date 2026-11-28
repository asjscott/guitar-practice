import Foundation

/// CAGED shape generation for any tuning (ADR-0001).
extension Fretboard {
    /// The CAGED positions of a scale, placed between the capo and the last fret, ordered up
    /// the neck (by lowest fret, then shape number). Each shape appears at its lowest fit and,
    /// when it fits, an octave higher.
    ///
    /// Each shape starts on one of the five notes of the key's major pentatonic on string 6
    /// and walks up the strings taking two pentatonic notes per string; that fret window is the
    /// shape. Scales with notes outside the pentatonic (major, natural minor, blues) add them
    /// inside the window, and where that would still skip a note, stretch outside it. Minor
    /// scales use their relative major's shapes. The shapes are named C A G E D only in tunings
    /// with standard intervals, else Position 1–5.
    ///
    /// In a dropped tuning (Drop D) the shape is the standard one: strings 5–1 unchanged, and
    /// string 6 plays the standard shape's string-6 pitches, a whole tone's two frets higher.
    public func cagedPositions(of scale: Scale) -> [Position] {
        let pentatonic = Scale(.majorPentatonic, tonic: scale.key.relativeMajor.tonic).pitchClasses
        let extraNotes = Set(scale.pitchClasses).subtracting(pentatonic)

        // A dropped low string plays the standard shape's string-6 pitches: the shape is built
        // on the undropped neck, then string 6 moves up by the drop (Drop D: 2 frets).
        let shapeBoard = Fretboard(tuning: tuning.undroppingLowString ?? tuning)
        let drop = (shapeBoard.tuning.openPitch(ofString: strings.lowerBound)
            - tuning.openPitch(ofString: strings.lowerBound)).semitones

        let positions = CAGEDShape.allCases.flatMap { shape in
            func moved(_ location: FretboardLocation) -> FretboardLocation {
                location.string == strings.lowerBound
                    ? FretboardLocation(string: location.string, fret: location.fret + drop) : location
            }
            let relative = shapeBoard.relativeLocations(of: shape, pentatonic: pentatonic, extraNotes: extraNotes)
            let placements = placements(of: relative.inWindow.map(moved), choices: relative.stretches.map { $0.map(moved) })
            return placements.enumerated().map { octave, locations in
                let id = Position.ID(system: .caged, number: shape.number, octave: octave)
                return Position(id: id,
                         scale: scale,
                         name: id.name(in: tuning),
                         cagedShape: shape,
                         locations: locations)
            }
        }
        return positions.sortedUpTheNeck()
    }

    /// One CAGED shape in relative frets: the pentatonic walk from the shape's starting degree,
    /// plus the scale's other notes inside the window, and for each note that would still be skipped, where it can be
    /// played, the best first.
    private func relativeLocations(of shape: CAGEDShape, pentatonic: [PitchClass], extraNotes: Set<PitchClass>)
        -> (inWindow: [FretboardLocation], stretches: [[FretboardLocation]]) {
        let start = shape.number - 1 // index of the starting degree in the pentatonic
        let core = walk(pentatonic, from: start, notesPerString: 2)
        let extras = strings.flatMap { string in
            window(of: core, onString: string).compactMap { fret in
                extraNotes.contains(tuning.openPitch(ofString: string).pitchClass + Interval(fret))
                    ? FretboardLocation(string: string, fret: fret) : nil
            }
        }
        let inWindow = core + extras
        let skipped = skippedNotes(in: inWindow, of: extraNotes.union(pentatonic))
        return (inWindow, skipped.map { stretches(to: $0, from: inWindow, core: core) })
    }

    /// The notes not played between the lowest and the highest of some locations, as MIDI numbers (relative frets can
    /// be below the nut).
    private func skippedNotes(in locations: [FretboardLocation], of notes: Set<PitchClass>) -> [Int] {
        let played = Set(locations.map(midi))
        guard let lowest = played.min(), let highest = played.max() else { return [] }
        return (lowest...highest).filter { !played.contains($0) && notes.contains(PitchClass($0)) }
    }

    /// Where a skipped note can be played: in the window or as near it as it gets, the string whose notes then span the
    /// fewest frets first (ties go to the lower string).
    private func stretches(to note: Int, from locations: [FretboardLocation],
                           core: [FretboardLocation]) -> [FretboardLocation] {
        let options = strings.map { string -> (location: FretboardLocation, outside: Int, span: Int) in
            let fret = note - tuning.openPitch(ofString: string).midi
            let window = window(of: core, onString: string)
            let onString = (locations.filter { $0.string == string } + [FretboardLocation(string: string, fret: fret)]).fretSpan
            return (FretboardLocation(string: string, fret: fret),
                    max(0, window.lowerBound - fret, fret - window.upperBound), onString.count)
        }
        let nearest = options.map(\.outside).min()
        return options.filter { $0.outside == nearest }.sorted { $0.span < $1.span }.map(\.location)
    }

    private func midi(_ location: FretboardLocation) -> Int {
        tuning.openPitch(ofString: location.string).midi + location.fret
    }

    /// The frets on a string where a shape's other scale notes are added: the fret window of
    /// the pentatonic notes on every string above the lowest, which on the lowest string also
    /// stretches to cover that string's own two notes.
    ///
    /// The lowest string is left out of the window so that an odd low string moves only its
    /// own notes. In standard tuning strings 6 and 1 hold the same frets, so this is the whole
    /// shape's window.
    private func window(of core: [FretboardLocation], onString string: Int) -> ClosedRange<Int> {
        let lowest = strings.lowerBound
        let upper = core.filter { $0.string != lowest || strings.count == 1 }.map(\.fret)
        let frets = string == lowest ? upper + core.filter { $0.string == lowest }.map(\.fret) : upper
        return frets.min()!...frets.max()!
    }
}
