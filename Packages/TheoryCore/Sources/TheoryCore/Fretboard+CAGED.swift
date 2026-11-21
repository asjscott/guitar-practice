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
    public func cagedPositions(of scale: Scale) -> [Position] {
        let pentatonic = Scale(.majorPentatonic, tonic: scale.key.relativeMajor.tonic).pitchClasses
        let extraNotes = Set(scale.pitchClasses).subtracting(pentatonic)
        let usesNames = tuning.hasStandardIntervals

        let positions = CAGEDShape.allCases.flatMap { shape in
            let start = shape.number - 1 // index of the starting degree in the pentatonic
            let core = pentatonicWalk(pentatonic, from: start)
            let extras = strings.flatMap { string in
                window(of: core, onString: string).compactMap { fret in
                    extraNotes.contains(tuning.openPitch(ofString: string).pitchClass + Interval(fret))
                        ? FretboardLocation(string: string, fret: fret) : nil
                }
            }
            return placements(of: core + extras).enumerated().map { octave, locations in
                Position(id: .init(system: .caged, number: shape.number, octave: octave),
                         scale: scale,
                         name: usesNames ? "\(shape.letter) shape" : "Position \(shape.number)",
                         cagedShape: shape,
                         locations: locations)
            }
        }
        return positions.sorted { ($0.frets.lowerBound, $0.number) < ($1.frets.lowerBound, $1.number) }
    }

    /// The frets on a string where a shape's other scale notes are added: the fret window of
    /// the pentatonic notes on every string above the lowest, which on the lowest string also
    /// stretches to cover that string's own two notes.
    ///
    /// The lowest string is left out of the window so that a dropped low string (Drop D) moves
    /// only its own notes: strings 5–1 keep their standard-tuning look. In standard tuning
    /// strings 6 and 1 hold the same frets, so this is the whole shape's window.
    private func window(of core: [FretboardLocation], onString string: Int) -> ClosedRange<Int> {
        let lowest = strings.lowerBound
        let upper = core.filter { $0.string != lowest || strings.count == 1 }.map(\.fret)
        let frets = string == lowest ? upper + core.filter { $0.string == lowest }.map(\.fret) : upper
        return frets.min()!...frets.max()!
    }

    /// Two pentatonic notes per string from string 6 up, starting on `pentatonic[start]`, in
    /// relative frets. Each string's first note sits nearest the previous string's first note,
    /// which keeps the shape compact in any tuning (and is the plain pitch walk in rising ones).
    private func pentatonicWalk(_ pentatonic: [PitchClass], from start: Int) -> [FretboardLocation] {
        var locations: [FretboardLocation] = []
        var anchor: Int?
        for string in strings {
            let index = start + 2 * (string - strings.lowerBound)
            let note = pentatonic[index % 5], next = pentatonic[(index + 1) % 5]
            let first = relativeFret(of: note, onString: string, near: anchor)
            let second = first + note.interval(upTo: next).semitones
            locations += [FretboardLocation(string: string, fret: first), FretboardLocation(string: string, fret: second)]
            anchor = first
        }
        return locations
    }
}
