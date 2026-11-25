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
#endif
