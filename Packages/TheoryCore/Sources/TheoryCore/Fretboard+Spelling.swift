import Foundation

extension Fretboard {
    /// The spelled name of the note at a location in a key; with no key (nil), sharps.
    public func name(at location: FretboardLocation, in key: Key?) -> NoteName {
        Key.spell(pitch(at: location).pitchClass, in: key)
    }

    /// The spelled name of the note at a location with a scale as context: scale notes follow
    /// the scale's degree formula (A blues has E♭), other notes the scale's key.
    public func name(at location: FretboardLocation, in scale: Scale) -> NoteName {
        scale.spell(pitch(at: location).pitchClass)
    }

    /// The open strings' names in a key (nil = sharps), string 6 first.
    public func stringNames(in key: Key?) -> [NoteName] {
        tuning.openPitches.map { Key.spell($0.pitchClass, in: key) }
    }

    /// Every playable location of a scale's notes across the whole neck, string 6 first, then by fret.
    public func locations(of scale: Scale) -> [FretboardLocation] {
        let pitchClasses = Set(scale.pitchClasses)
        return allLocations.filter { pitchClasses.contains(pitch(at: $0).pitchClass) }
    }
}
