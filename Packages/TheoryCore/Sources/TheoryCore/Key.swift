import Foundation

/// A tonic plus a mode (major or minor) that decides how notes are spelled (see GLOSSARY.md).
///
/// A minor key takes its relative major's key signature, so D♯ minor is spelled like F♯ major.
public struct Key: Hashable, Sendable, Codable {
    public enum Mode: String, Hashable, Sendable, Codable, CaseIterable {
        case major, minor
    }

    public let tonic: NoteName
    public let mode: Mode

    public init(tonic: NoteName, mode: Mode) {
        self.tonic = tonic
        self.mode = mode
    }

    public static func major(_ tonic: NoteName) -> Key { Key(tonic: tonic, mode: .major) }
    public static func minor(_ tonic: NoteName) -> Key { Key(tonic: tonic, mode: .minor) }

    /// The 12 major keys the app offers, in picker order: C G D A E B F♯ F B♭ E♭ A♭ D♭.
    public static let appMajorKeys: [Key] = [
        .c, .g, .d, .a, .e, .b, .fSharp, .f, .bFlat, .eFlat, .aFlat, .dFlat,
    ].map(Key.major)

    /// The app's 12 minor keys: the relative minors of `appMajorKeys`, in the same order
    /// (Am Em Bm F♯m C♯m G♯m D♯m Dm Gm Cm Fm B♭m).
    public static let appMinorKeys: [Key] = appMajorKeys.map(\.relativeMinor)

    /// The app's 12 keys in one mode, in picker order: `appMajorKeys` or `appMinorKeys`.
    /// The key picker shows their tonics (C G D … or A E B …).
    public static func appKeys(_ mode: Mode) -> [Key] {
        mode == .major ? appMajorKeys : appMinorKeys
    }

    /// The app key with this tonic pitch class in this mode: pitch class 1 is D♭ major or C♯ minor.
    public static func app(tonic: PitchClass, mode: Mode) -> Key {
        appKeys(mode).first { $0.tonic.pitchClass == tonic }!
    }

    /// This key in another mode on the same tonic pitch class, spelled as the app's key in
    /// that mode (D♭ major → C♯ minor, D♯ minor → E♭ major). The same mode returns the key itself.
    public func withMode(_ mode: Mode) -> Key {
        mode == self.mode ? self : .app(tonic: tonic.pitchClass, mode: mode)
    }

    /// The circle of fifths from this key: the app's twelve keys in this key's mode, each a fifth above the last, starting
    /// here and going sharpward (E B F♯ D♭ A♭ E♭ B♭ F C G D A; C♯m G♯m D♯m B♭m …). Spelled as the app's keys.
    public var circleOfFifths: [Key] {
        (0..<12).map { step in .app(tonic: tonic.pitchClass + Interval(7 * step), mode: mode) }
    }

    /// All 15 major key signatures, from 7 flats (C♭) to 7 sharps (C♯).
    public static let allMajorKeySignatures: [Key] = [
        .cFlat, .gFlat, .dFlat, .aFlat, .eFlat, .bFlat, .f, .c, .g, .d, .a, .e, .b, .fSharp, .cSharp,
    ].map(Key.major)

    /// The relative minor (a minor 3rd below a major tonic); a minor key returns itself.
    public var relativeMinor: Key {
        switch mode {
        case .minor: self
        case .major: .minor(NoteName(tonic.letter.advanced(by: -2), spelling: tonic.pitchClass - Interval(3)))
        }
    }

    /// The relative major (a minor 3rd above a minor tonic); a major key returns itself.
    public var relativeMajor: Key {
        switch mode {
        case .major: self
        case .minor: .major(NoteName(tonic.letter.advanced(by: 2), spelling: tonic.pitchClass + Interval(3)))
        }
    }

    /// The key's own scale: major or natural minor on its tonic.
    public var scale: Scale { Scale(mode == .major ? .major : .naturalMinor, tonic: tonic) }

    /// The seven notes of the key, from the tonic: its major or natural minor scale.
    public var notes: [NoteName] { scale.notes }

    /// Sharps (positive) or flats (negative) in the key signature: F major −1, B major +5.
    public var signature: Int { notes.map(\.accidental).reduce(0, +) }

    /// The notes the key signature alters, in the order they are written (F♯ C♯ … or B♭ E♭ …).
    public var signatureAccidentals: [NoteName] {
        let order: [Letter] = signature >= 0 ? [.f, .c, .g, .d, .a, .e, .b] : [.b, .e, .a, .d, .g, .c, .f]
        let altered = notes.filter { $0.accidental != 0 }
        return order.compactMap { letter in altered.first { $0.letter == letter } }
    }

    /// The spelling of a pitch class in this key: key notes follow the key signature;
    /// other notes use flats in flat keys and sharps otherwise.
    public func spell(_ pitchClass: PitchClass) -> NoteName {
        if let note = notes.first(where: { $0.pitchClass == pitchClass }) { return note }
        return signature < 0 ? NoteName(flatSpelling: pitchClass) : NoteName(sharpSpelling: pitchClass)
    }

    /// The spelling of a pitch class in an optional key: with no key, sharps.
    public static func spell(_ pitchClass: PitchClass, in key: Key?) -> NoteName {
        key?.spell(pitchClass) ?? NoteName(sharpSpelling: pitchClass)
    }

    /// For example "C", "B♭", "D♯m".
    public var shortName: String { mode == .major ? tonic.description : "\(tonic)m" }
}

extension Key: CustomStringConvertible {
    /// For example "C major", "D♯ minor".
    public var description: String { "\(tonic) \(mode.rawValue)" }
}
