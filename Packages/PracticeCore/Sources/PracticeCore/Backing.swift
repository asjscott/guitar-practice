import TheoryCore

/// One chord of a progression as the backing plays it: a triad, already spelled in the key, for some bars of 4/4.
public struct BackingChord: Hashable, Sendable {
    public let triad: Triad
    public let bars: Int

    public init(_ triad: Triad, bars: Int = 1) {
        precondition(bars > 0)
        self.triad = triad
        self.bars = bars
    }
}

/// How the backing plays a chord. Rock for now; pop ballad and blues shuffle come later.
public enum BackingStyle: String, Hashable, Sendable, Codable, CaseIterable {
    case rock
}

/// Which instrument plays a note. Each is one sampler in the app.
public enum BackingPart: String, Hashable, Sendable, CaseIterable {
    case bass, keys, drums
}

/// One note of the backing: when it is heard (on the click clock) and for how long. Drums' pitches are General MIDI
/// percussion keys.
public struct BackingNote: Hashable, Sendable {
    public let part: BackingPart
    public let pitch: Pitch
    /// 1–127.
    public let velocity: Int
    public let time: Duration
    public let length: Duration
}

/// The backing for a progression, as data: a bar of drumsticks to count in, then the progression round and round,
/// in one style at one tempo, from beat 1 of the count-in at `start`. Always 4/4; a beat is a click.
public struct Backing: Hashable, Sendable {
    /// General MIDI percussion keys.
    public enum Drum {
        public static let kick = Pitch(36)
        public static let sticks = Pitch(37)
        public static let snare = Pitch(38)
        public static let closedHiHat = Pitch(42)
    }

    public static let beatsPerBar = 4

    public let chords: [BackingChord]
    public let style: BackingStyle
    public let bpm: Int
    /// When beat 1 of the count-in is heard.
    public let start: Duration

    public init(chords: [BackingChord], style: BackingStyle, bpm: Int, start: Duration) {
        precondition(!chords.isEmpty && bpm > 0)
        self.chords = chords
        self.style = style
        self.bpm = bpm
        self.start = start
    }

    /// When an eighth note is heard, counting from beat 1 of the count-in. Worked out from the start, so that it
    /// doesn't drift.
    func time(ofEighth index: Int) -> Duration { start + .seconds(60) * index / (bpm * 2) }

    /// A bar of drumsticks on the beats.
    public var countIn: [BackingNote] {
        (0..<Self.beatsPerBar).map { beat in
            BackingNote(part: .drums, pitch: Drum.sticks, velocity: 100, time: time(ofEighth: beat * 2), length: .milliseconds(100))
        }
    }

    /// The first time through, after the count-in.
    public var timeThrough: [BackingNote] { timeThrough(0) }

    /// Time through `index` (from 0), in order of time.
    func timeThrough(_ index: Int) -> [BackingNote] {
        var bar = 1 + index * barsPerTimeThrough
        var notes: [BackingNote] = []
        for chord in chords {
            for _ in 0..<chord.bars {
                notes += self.bar(bar, of: chord.triad)
                bar += 1
            }
        }
        return notes.sorted { $0.time < $1.time }
    }

    public var barsPerTimeThrough: Int { chords.map(\.bars).reduce(0, +) }

    /// When time through `index` (from 0) begins.
    public func start(ofTimeThrough index: Int) -> Duration {
        time(ofEighth: (1 + index * barsPerTimeThrough) * Self.eighthsPerBar)
    }

    /// The notes that begin in a stretch of time, in order: the count-in, then the progression without end.
    public func notes(from start: Duration, before end: Duration) -> [BackingNote] {
        guard start < end else { return [] }
        var notes = countIn
        // An estimate, then made exact.
        let length = self.start(ofTimeThrough: 1) - self.start(ofTimeThrough: 0)
        var index = max(0, Int((start - self.start(ofTimeThrough: 0)) / length) - 1)
        if index > 0 { notes = [] }
        while self.start(ofTimeThrough: index) < end {
            notes += timeThrough(index)
            index += 1
        }
        return notes.filter { $0.time >= start && $0.time < end }
    }

    private static let eighthsPerBar = beatsPerBar * 2

    /// One bar of a chord in the style; bar 0 is the count-in.
    private func bar(_ bar: Int, of triad: Triad) -> [BackingNote] {
        let first = bar * Self.eighthsPerBar
        func note(_ part: BackingPart, _ pitch: Pitch, _ velocity: Int, eighth: Int, eighths length: Int) -> BackingNote {
            let time = time(ofEighth: first + eighth)
            return BackingNote(part: part, pitch: pitch, velocity: velocity, time: time,
                               length: (self.time(ofEighth: first + eighth + length) - time) * 0.9)
        }
        switch style {
        case .rock:
            let drums = (0..<Self.eighthsPerBar).flatMap { eighth -> [BackingNote] in
                var hits = [note(.drums, Drum.closedHiHat, eighth.isMultiple(of: 2) ? 80 : 60, eighth: eighth, eighths: 1)]
                switch eighth {
                case 0, 4: hits.append(note(.drums, Drum.kick, 110, eighth: eighth, eighths: 1))
                case 2, 6: hits.append(note(.drums, Drum.snare, 100, eighth: eighth, eighths: 1))
                default: break
                }
                return hits
            }
            let root = Self.lowest(triad.root.pitchClass, from: Self.bassLowest)
            let bass = (0..<Self.eighthsPerBar).map { eighth in
                note(.bass, root, eighth.isMultiple(of: 2) ? 100 : 85, eighth: eighth, eighths: 1)
            }
            let voicing = triad.pitchClasses.map { Self.lowest($0, from: Self.keysLowest) }
            let keys = [0, 4].flatMap { eighth in voicing.map { note(.keys, $0, 70, eighth: eighth, eighths: 4) } }
            return drums + bass + keys
        }
    }

    /// E1, the bass's low E.
    private static let bassLowest = Pitch(28)
    /// G3: each chord tone is the lowest from here up, so the keys keep to the middle, out of the guitar triads' way
    /// as far as they can.
    private static let keysLowest = Pitch(55)

    /// The lowest pitch of a pitch class at or above another pitch.
    private static func lowest(_ pitchClass: PitchClass, from floor: Pitch) -> Pitch {
        floor + floor.pitchClass.interval(upTo: pitchClass)
    }
}
