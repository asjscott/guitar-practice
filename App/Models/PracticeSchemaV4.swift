import Foundation
import SwiftData

/// The fourth version of what is saved: raw facts only (ADR 0003). It adds fade levels (ADR 0007), circle ids and a
/// pass's direction to version 3, and lets a session have no budget. It shares version 1's `SessionBlockRecord`,
/// `WrongAnswerRecord` and enums, and version 3's `VoicingRecord`.
///
/// Once the app has saved real practice with it, never edit it: copy it to `PracticeSchemaV5`, and add that and a
/// stage to `PracticeMigrationPlan`. Enums are saved as their raw values, notes as MIDI numbers, pitch
/// classes (C = 0) or text ("B♭"), strings as internal indices (0 = string 6).
enum PracticeSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] { [Session.self, Attempt.self, DayTheme.self] }

    /// One session. It is saved with its first attempt, so one with no attempts never is.
    @Model final class Session {
        @Attribute(.unique) var id: UUID

        /// The local calendar day it started on, "2026-07-25".
        var day: String
        var startedAt: Date

        /// Nil while it goes, or if the app quit during it.
        var endedAt: Date?

        /// A `SessionState` raw value.
        var stateRaw: String

        /// From Start to the end, Ready cards and extended blocks included; nil until it ends.
        var totalSeconds: Double?

        // What was chosen at setup.
        /// Nil once sessions have no budget.
        var budgetMinutes: Int?
        var naturalsOnly: Bool
        /// Whole neck rather than First 12 frets.
        var wholeNeck: Bool

        // The theme as the session used it: the day's `DayTheme` can change position with the tuning.
        var themeTonic: Int?
        var themeMode: String?
        var themePositionSystem: String?
        var themePositionNumber: Int?
        var themePositionOctave: Int?
        /// A `StringSet` raw value; nil in version 1's sessions.
        var themeStringSet: String?
        /// The progression's id in TheoryCore's library ("I–V–vi–IV"); nil in older versions' sessions.
        var themeProgression: String?

        /// Every planned block, in order.
        var blocks: [SessionBlockRecord]

        @Relationship(deleteRule: .nullify, inverse: \Attempt.session)
        var attempts: [Attempt] = []

        init(day: String, startedAt: Date, budgetMinutes: Int?, naturalsOnly: Bool, wholeNeck: Bool,
             blocks: [SessionBlockRecord]) {
            id = UUID()
            self.day = day
            self.startedAt = startedAt
            stateRaw = SessionState.inProgress.rawValue
            self.budgetMinutes = budgetMinutes
            self.naturalsOnly = naturalsOnly
            self.wholeNeck = wholeNeck
            self.blocks = blocks
        }
    }

    /// One attempt, from a session or free practice.
    @Model final class Attempt {
        @Attribute(.unique) var id: UUID

        /// When it ended.
        var date: Date

        /// An `AttemptSource` raw value.
        var sourceRaw: String

        /// A `DrillKind` id.
        var drill: String

        // The instrument: a string and fret mean nothing without it.
        /// Open pitches, string 6 first.
        var tuning: [Int]
        var capo: Int

        // What was asked.
        /// As spelled to the player: "B♭".
        var targetName: String
        var targetPitchClass: Int
        var targetString: Int
        /// The fret asked for, or where it was answered. Nil when any fret on the string would do and none was played.
        var targetFret: Int?
        /// The pitch at that fret.
        var targetPitch: Int?

        // What happened.
        /// A PracticeCore `Attempt.Outcome` raw value.
        var outcomeRaw: String
        var firstRight: Bool
        /// Nil unless answered.
        var responseSeconds: Double?
        /// In the order they were given.
        var wrongAnswers: [WrongAnswerRecord]

        /// Shared by the attempts of one sweep, pass, triad prompt or climb; nil when the attempt stands alone.
        @Attribute(originalName: "sweepID") var groupID: UUID?
        /// How many attempts the whole group has, and which this is (0 = first). Nil in sweeps.
        var groupSize: Int?
        var groupPlace: Int?
        /// Shared by the sweeps or passes of one circle of fifths; nil outside one.
        var circleID: UUID?

        // Passes only.
        /// A `Scale.Kind` raw value and the tonic's pitch class.
        var scaleKind: String?
        var scaleTonic: Int?
        /// A `Position.System` raw value and the position's number and octave.
        var positionSystem: String?
        var positionNumber: Int?
        var positionOctave: Int?
        /// The degree the pass starts on: ♭3 is 3 and −1.
        var startDegree: Int?
        var startDegreeAlteration: Int?
        /// "up" or "down", in drills whose passes go one way; nil where a pass goes both ways.
        var passDirection: String?
        /// BPM, counting clicks.
        var tempo: Int?
        /// The time signature: 6 and 8 in 6/8.
        var beatsPerBar: Int?
        var beatUnit: Int?
        /// A `FadeStage` raw value: what the pass, voicing or chord was played at, before fade levels.
        var fadeStageRaw: String?
        /// The fade level the pass, voicing or chord was played at, 0–6; nil in older versions' attempts, whose
        /// `fadeStageRaw` reads as a level (Shown 0, Faded 2, Hidden 6).
        var fadeLevel: Int?
        /// Whether a hint had been used in the pass by the time this note was dealt with.
        var hinted: Bool?
        /// The onset less the time the nearest click was heard: positive = late. Nil unless answered. From V3 on, the
        /// input delay is taken off the onset first.
        var clickOffsetSeconds: Double?

        // Triads only.
        /// As spelled to the player: "B♭".
        var chordRootName: String?
        var chordRoot: Int?
        /// A `Triad.Quality`, a `Triad.Inversion` and a `StringSet` raw value.
        var chordQuality: String?
        var inversion: String?
        var stringSet: String?

        // Passes and chords.
        /// The input delay taken off the onset before it was compared with clicks or backing; nil in older versions'
        /// attempts and where no onset is compared. The times saved from onsets (response time, click offset, first
        /// onset) have it taken off; adding it back gives the onset as the listener reported it (ADR 0003).
        var inputDelaySeconds: Double?

        // Chords only: one attempt per chord of a time through, whose chords share a group. The group's size is the
        // progression's chord count and the place the chord's (0 = first). The chord in the key is in the triad
        // fields above, the position in the pass fields, and tempo, time signature, fade level and hint too.
        /// The progression's id in TheoryCore's library ("I–V–vi–IV").
        var progression: String?
        /// The key's tonic pitch class and `Key.Mode` raw value: one of the app's keys.
        var keyTonic: Int?
        var keyMode: String?
        /// The chord's Roman numeral as the progression writes it: "vi".
        var numeral: String?
        /// The voicing played; nil if it was missed.
        var playedVoicing: VoicingRecord?
        /// Every voicing that would have been clean.
        var acceptedVoicings: [VoicingRecord]?
        /// The backing's style, as a raw value.
        var backingStyle: String?
        /// "clean", "wrong" or "missed", as a raw value. `outcomeRaw` doesn't apply.
        var chordOutcomeRaw: String?
        /// The first note's onset, input delay taken off, less the chord's first beat: negative = early. Nil if
        /// nothing was played in the chord's window.
        var firstOnsetSeconds: Double?

        /// Nil in free practice.
        var session: Session?
        /// Index in the session's `blocks`; nil in free practice.
        var blockIndex: Int?

        init(date: Date, sourceRaw: String, drill: String, tuning: [Int], capo: Int, targetName: String,
             targetPitchClass: Int, targetString: Int, targetFret: Int?, targetPitch: Int?, outcomeRaw: String,
             firstRight: Bool, responseSeconds: Double?, wrongAnswers: [WrongAnswerRecord], groupID: UUID?,
             blockIndex: Int?) {
            id = UUID()
            self.date = date
            self.sourceRaw = sourceRaw
            self.drill = drill
            self.tuning = tuning
            self.capo = capo
            self.targetName = targetName
            self.targetPitchClass = targetPitchClass
            self.targetString = targetString
            self.targetFret = targetFret
            self.targetPitch = targetPitch
            self.outcomeRaw = outcomeRaw
            self.firstRight = firstRight
            self.responseSeconds = responseSeconds
            self.wrongAnswers = wrongAnswers
            self.groupID = groupID
            self.blockIndex = blockIndex
        }
    }

    /// One calendar day's theme, saved when first shown.
    @Model final class DayTheme {
        /// The local calendar day, "2026-07-25".
        @Attribute(.unique) var day: String

        /// Which reroll this is; 0 = the day's first theme. With the day it gives the seed again.
        var rerolls: Int

        /// The tonic's pitch class and the `Key.Mode` raw value: one of the app's keys.
        var tonic: Int
        var mode: String

        /// A `Position.System` raw value and the position's number and octave.
        var positionSystem: String
        var positionNumber: Int
        var positionOctave: Int

        /// A `StringSet` raw value; nil in version 1's themes.
        var stringSet: String?

        /// The progression's id in TheoryCore's library ("I–V–vi–IV"), in the key's mode; nil in older versions' themes.
        var progression: String?

        init(day: String, rerolls: Int, tonic: Int, mode: String, positionSystem: String, positionNumber: Int,
             positionOctave: Int) {
            self.day = day
            self.rerolls = rerolls
            self.tonic = tonic
            self.mode = mode
            self.positionSystem = positionSystem
            self.positionNumber = positionNumber
            self.positionOctave = positionOctave
        }
    }
}
