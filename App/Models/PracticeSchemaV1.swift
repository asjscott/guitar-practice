import Foundation
import SwiftData

/// The first version of what is saved: raw facts only (ADR 0003).
///
/// Once the app has saved real practice, never edit a released version: copy it to `PracticeSchemaV2`, and add
/// that and a stage to `PracticeMigrationPlan`. Enums are saved as their raw values, notes as MIDI numbers, pitch
/// classes (C = 0) or text ("B♭"), strings as internal indices (0 = string 6).
enum PracticeSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
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

        /// From Start to the end, Ready cards and overtime included; nil until it ends.
        var totalSeconds: Double?

        // What was chosen at setup.
        var budgetMinutes: Int
        var naturalsOnly: Bool
        /// Whole neck rather than First 12 frets.
        var wholeNeck: Bool

        // The theme as the session used it: the day's `DayTheme` can change position with the tuning.
        var themeTonic: Int?
        var themeMode: String?
        var themePositionSystem: String?
        var themePositionNumber: Int?
        var themePositionOctave: Int?

        /// Every planned block, in order.
        var blocks: [SessionBlockRecord]

        @Relationship(deleteRule: .nullify, inverse: \Attempt.session)
        var attempts: [Attempt] = []

        init(day: String, startedAt: Date, budgetMinutes: Int, naturalsOnly: Bool, wholeNeck: Bool,
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
        var firstTryRight: Bool
        /// Nil unless answered.
        var responseSeconds: Double?
        /// In the order they were given.
        var wrongAnswers: [WrongAnswerRecord]

        /// Shared by the attempts of one sweep; nil in other drills.
        var sweepID: UUID?

        /// Nil in free practice.
        var session: Session?
        /// Index in the session's `blocks`; nil in free practice.
        var blockIndex: Int?

        init(date: Date, sourceRaw: String, drill: String, tuning: [Int], capo: Int, targetName: String,
             targetPitchClass: Int, targetString: Int, targetFret: Int?, targetPitch: Int?, outcomeRaw: String,
             firstTryRight: Bool, responseSeconds: Double?, wrongAnswers: [WrongAnswerRecord], sweepID: UUID?,
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
            self.firstTryRight = firstTryRight
            self.responseSeconds = responseSeconds
            self.wrongAnswers = wrongAnswers
            self.sweepID = sweepID
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

/// A planned block of a session, as saved. Part of `PracticeSchemaV1`.
struct SessionBlockRecord: Codable, Hashable, Sendable {
    /// A `DrillKind` id.
    var drill: String
    /// As planned, extends left out.
    var plannedSeconds: Double
    /// How often it was extended.
    var extends = 0
    /// The block time spent, overtime included; nil if it never started.
    var spentSeconds: Double?
}

/// A wrong answer, as saved: a played pitch or a typed name. Part of `PracticeSchemaV1`.
struct WrongAnswerRecord: Codable, Hashable, Sendable {
    /// A played pitch's MIDI number; nil for a typed name.
    var pitch: Int?
    /// A typed name ("B♭"); nil for a played pitch.
    var name: String?
}

/// Saved raw values: never change them.
enum SessionState: String, Sendable {
    /// Going, or cut off by a quit or crash and not seen since: opening the log makes it `endedEarly`.
    case inProgress
    case completed
    case endedEarly
}

/// Saved raw values: never change them.
enum AttemptSource: String, Sendable {
    case session, freePractice
}
