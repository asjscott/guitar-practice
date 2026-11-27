import Foundation
import PracticeCore
import SwiftData
import TheoryCore

// The current version's models. `LoggedAttempt` is the saved record; PracticeCore's `Attempt` is the drill's.
typealias PracticeSession = PracticeSchemaV4.Session
typealias LoggedAttempt = PracticeSchemaV4.Attempt
typealias DayTheme = PracticeSchemaV4.DayTheme

enum PracticeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PracticeSchemaV1.self, PracticeSchemaV2.self, PracticeSchemaV3.self, PracticeSchemaV4.self]
    }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: PracticeSchemaV1.self, toVersion: PracticeSchemaV2.self),
         .lightweight(fromVersion: PracticeSchemaV2.self, toVersion: PracticeSchemaV3.self),
         .lightweight(fromVersion: PracticeSchemaV3.self, toVersion: PracticeSchemaV4.self)]
    }
}

extension Theme {
    /// As `Session` and `DayTheme` save it; nil if that is unusable.
    /// A progression that isn't in the library is as none: one is picked again when the theme is next shown.
    fileprivate init?(tonic: Int?, mode: String?, system: String?, number: Int?, octave: Int?, stringSet: String?,
                      progression: String?) {
        guard let tonic, let mode = mode.flatMap(Key.Mode.init), let system = system.flatMap(Position.System.init),
              let number, let octave else { return nil }
        self.init(key: .app(tonic: PitchClass(tonic), mode: mode),
                  position: Position.ID(system: system, number: number, octave: octave),
                  stringSet: stringSet.flatMap(StringSet.init), progression: progression.flatMap(Progression.named))
    }
}

extension DayTheme {
    convenience init(day: String, theme: Theme, rerolls: Int = 0) {
        self.init(day: day, rerolls: rerolls, tonic: theme.key.tonic.pitchClass.value, mode: theme.key.mode.rawValue,
                  positionSystem: theme.position.system.rawValue, positionNumber: theme.position.number,
                  positionOctave: theme.position.octave)
        stringSet = theme.stringSet?.rawValue
        progression = theme.progression?.id
    }

    /// Nil only if what is saved is unusable.
    var theme: Theme? {
        get {
            Theme(tonic: tonic, mode: mode, system: positionSystem, number: positionNumber, octave: positionOctave,
                  stringSet: stringSet, progression: progression)
        }
        set {
            guard let newValue else { return }
            tonic = newValue.key.tonic.pitchClass.value
            mode = newValue.key.mode.rawValue
            positionSystem = newValue.position.system.rawValue
            positionNumber = newValue.position.number
            positionOctave = newValue.position.octave
            stringSet = newValue.stringSet?.rawValue
            progression = newValue.progression?.id
        }
    }
}

extension PracticeSession {
    var state: SessionState {
        get { SessionState(rawValue: stateRaw) ?? .endedEarly }
        set { stateRaw = newValue.rawValue }
    }

    /// Nil in a session without a theme.
    var theme: Theme? {
        get {
            Theme(tonic: themeTonic, mode: themeMode, system: themePositionSystem, number: themePositionNumber,
                  octave: themePositionOctave, stringSet: themeStringSet, progression: themeProgression)
        }
        set {
            themeTonic = newValue?.key.tonic.pitchClass.value
            themeMode = newValue?.key.mode.rawValue
            themePositionSystem = newValue?.position.system.rawValue
            themePositionNumber = newValue?.position.number
            themePositionOctave = newValue?.position.octave
            themeStringSet = newValue?.stringSet?.rawValue
            themeProgression = newValue?.progression?.id
        }
    }
}

extension LoggedAttempt {
    /// The record of an attempt at a drill, ending now.
    convenience init(_ attempt: Attempt, in drill: any Drill, date: Date, source: AttemptSource, groupID: UUID?,
                     blockIndex: Int?) {
        let fretboard = drill.fretboard
        let location = attempt.prompt.target ?? attempt.location
        self.init(date: date, sourceRaw: source.rawValue, drill: drill.kind.id,
                  tuning: fretboard.tuning.openPitches.map(\.midi), capo: fretboard.capo,
                  targetName: attempt.prompt.noteName, targetPitchClass: attempt.prompt.pitchClass.value,
                  targetString: attempt.prompt.string, targetFret: location?.fret,
                  targetPitch: location.map { fretboard.pitch(at: $0).midi },
                  outcomeRaw: attempt.outcome.rawValue, firstRight: attempt.firstRight,
                  responseSeconds: attempt.responseTime.map { $0 / .seconds(1) },
                  wrongAnswers: attempt.rawWrongAnswers.map(WrongAnswerRecord.init), groupID: groupID,
                  blockIndex: blockIndex)
        groupSize = attempt.group?.size
        groupPlace = attempt.group?.place
        switch attempt.facts {
        case .pass(let facts): setFacts(facts)
        case .triad(let facts): setFacts(facts)
        case .chord(let facts): setFacts(facts)
        case nil: break
        }
    }

    private func setFacts(_ facts: PassFacts) {
        scaleKind = facts.scale.kind.rawValue
        scaleTonic = facts.scale.tonic.pitchClass.value
        positionSystem = facts.position.system.rawValue
        positionNumber = facts.position.number
        positionOctave = facts.position.octave
        startDegree = facts.startDegree.number
        startDegreeAlteration = facts.startDegree.alteration
        tempo = facts.tempo
        beatsPerBar = facts.signature.beats
        beatUnit = facts.signature.unit
        fadeLevel = facts.fadeLevel.number
        hinted = facts.hinted
        clickOffsetSeconds = facts.clickOffset.map { $0 / .seconds(1) }
        inputDelaySeconds = facts.inputDelay / .seconds(1)
    }

    private func setFacts(_ facts: TriadFacts) {
        chordRootName = facts.triad.root.description
        chordRoot = facts.triad.root.pitchClass.value
        chordQuality = facts.triad.quality.rawValue
        inversion = facts.inversion.rawValue
        stringSet = facts.stringSet.rawValue
        fadeLevel = facts.fadeLevel?.number
        hinted = facts.fadeLevel.map { _ in facts.hinted }
    }

    private func setFacts(_ facts: ChordFacts) {
        progression = facts.progression.id
        keyTonic = facts.key.tonic.pitchClass.value
        keyMode = facts.key.mode.rawValue
        numeral = facts.numeral.text
        chordRootName = facts.triad.root.description
        chordRoot = facts.triad.root.pitchClass.value
        chordQuality = facts.triad.quality.rawValue
        positionSystem = facts.position.system.rawValue
        positionNumber = facts.position.number
        positionOctave = facts.position.octave
        playedVoicing = facts.played.map(VoicingRecord.init)
        acceptedVoicings = facts.accepted.map(VoicingRecord.init)
        // Nil without backing (Chords in position).
        backingStyle = facts.style?.rawValue
        tempo = facts.tempo
        (beatsPerBar, beatUnit) = facts.tempo == nil ? (nil, nil) : (4, 4)
        fadeLevel = facts.fadeLevel.number
        hinted = facts.hinted
        chordOutcomeRaw = facts.outcome.rawValue
        firstOnsetSeconds = facts.firstOnset.map { $0 / .seconds(1) }
        inputDelaySeconds = facts.inputDelay / .seconds(1)
    }

    var source: AttemptSource? { AttemptSource(rawValue: sourceRaw) }

    /// What the pass, voicing or chord was played at: its level, or in older versions' attempts its stage as a level.
    var playedFadeLevel: FadeLevel? {
        fadeLevel.map(FadeLevel.init) ?? fadeStageRaw.flatMap(FadeStage.init).map(FadeLevel.init)
    }
    var outcome: Attempt.Outcome? { Attempt.Outcome(rawValue: outcomeRaw) }
}

extension VoicingRecord {
    init(_ voicing: TriadVoicing) {
        notes = voicing.locations.map { Location(string: $0.string, fret: $0.fret) }
    }
}

extension WrongAnswerRecord {
    init(_ answer: DrillAnswer) {
        switch answer {
        case .played(let pitch): self.init(pitch: pitch.midi)
        case .named(let name): self.init(name: name.description)
        }
    }
}

extension Calendar {
    /// The local calendar day, as `Session.day` and `DayTheme.day` save it: "2026-07-25".
    static func practiceDay(of date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    /// A count of local calendar days, one more each day.
    static func dayNumber(of date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.ordinality(of: .day, in: .era, for: date) ?? 0
    }
}
