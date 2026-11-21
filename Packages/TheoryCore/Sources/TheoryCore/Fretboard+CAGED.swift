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
    /// inside the window. Minor scales use their relative major's shapes. The shapes are named
    /// C A G E D only in tunings with standard intervals, else Position 1–5.
    ///
    /// In a dropped tuning (Drop D) the shape is the standard one: strings 5–1 unchanged, and
    /// string 6 plays the standard shape's string-6 pitches, a whole tone's two frets higher.
    public func cagedPositions(of scale: Scale) -> [Position] {
        let pentatonic = Scale(.majorPentatonic, tonic: scale.key.relativeMajor.tonic).pitchClasses
        let extraNotes = Set(scale.pitchClasses).subtracting(pentatonic)
        let usesNames = tuning.hasStandardIntervals

        // A dropped low string plays the standard shape's string-6 pitches: the shape is built
        // on the undropped neck, then string 6 moves up by the drop (Drop D: 2 frets).
        let shapeBoard = Fretboard(tuning: tuning.undroppingLowString ?? tuning)
        let drop = (shapeBoard.tuning.openPitch(ofString: strings.lowerBound)
            - tuning.openPitch(ofString: strings.lowerBound)).semitones

        let positions = CAGEDShape.allCases.flatMap { shape in
            let relative = shapeBoard.relativeLocations(of: shape, pentatonic: pentatonic, extraNotes: extraNotes)
                .map { $0.string == strings.lowerBound ? FretboardLocation(string: $0.string, fret: $0.fret + drop) : $0 }
            return placements(of: relative).enumerated().map { octave, locations in
                Position(id: .init(system: .caged, number: shape.number, octave: octave),
                         scale: scale,
                         name: usesNames ? "\(shape.letter) shape" : "Position \(shape.number)",
                         cagedShape: shape,
                         locations: locations)
            }
        }
        return positions.sortedUpTheNeck()
    }

    /// One CAGED shape in relative frets: the pentatonic walk from the shape's starting degree,
    /// plus the scale's other notes inside the window.
    private func relativeLocations(of shape: CAGEDShape, pentatonic: [PitchClass],
                                   extraNotes: Set<PitchClass>) -> [FretboardLocation] {
        let start = shape.number - 1 // index of the starting degree in the pentatonic
        let core = walk(pentatonic, from: start, notesPerString: 2)
        let extras = strings.flatMap { string in
            window(of: core, onString: string).compactMap { fret in
                extraNotes.contains(tuning.openPitch(ofString: string).pitchClass + Interval(fret))
                    ? FretboardLocation(string: string, fret: fret) : nil
            }
        }
        return core + extras
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
