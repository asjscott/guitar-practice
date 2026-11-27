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

/// How the backing plays a chord. Raw values are logged and remembered per progression: never change them.
///
/// By ear (for the player, at the gate): each should sound right from 60 to 120 BPM. Rock drives on eighths; the pop
/// ballad breathes, a bar feeling like two slow beats; the shuffle swings, its offbeats late (two thirds through the
/// beat), not straight.
public enum BackingStyle: String, Hashable, Sendable, Codable, CaseIterable {
    /// Eighth-note bass on the root, keys on 1 and 3, kick on 1 and 3, snare on 2 and 4, eighth hi-hats.
    case rock
    /// Half time: bass root on 1 and fifth on 3, keys held for the bar, kick on 1, snare on 3, hi-hats on the beats.
    case popBallad
    /// Shuffled eighths: bass walking root–fifth–sixth–fifth, keys on 1 and 3, kick on 1 and 3, snare on 2 and 4,
    /// shuffled hi-hats.
    case bluesShuffle
}

extension Progression {
    /// The style its backing has until one is chosen for it: the shuffle for a progression with a shuffle feel (the
    /// 12-bar blues), else rock.
    public var defaultStyle: BackingStyle {
        switch feel {
        case .straight: .rock
        case .shuffle: .bluesShuffle
        }
    }
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

    /// When an eighth note is heard, counting from beat 1 of the count-in.
    func time(ofEighth index: Int) -> Duration { time(ofTick: index * Self.ticksPerEighth) }

    /// When a tick (a sixth of a beat, so straight and shuffled eighths both fall on one) is heard, counting from
    /// beat 1 of the count-in. Worked out from the start, so that it doesn't drift.
    private func time(ofTick index: Int) -> Duration { start + .seconds(60) * index / (bpm * Self.ticksPerBeat) }

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

    private static let ticksPerBeat = 6
    private static let ticksPerEighth = ticksPerBeat / 2
    private static let ticksPerBar = ticksPerBeat * beatsPerBar
    /// Where a beat's second shuffled eighth falls: two thirds of the way through it.
    private static let shuffledOffbeat = ticksPerBeat * 2 / 3

    /// One bar of a chord in the style; bar 0 is the count-in.
    private func bar(_ bar: Int, of triad: Triad) -> [BackingNote] {
        let first = bar * Self.ticksPerBar
        /// A note at a tick of the bar, lasting most of `ticks`, so that repeated notes are heard apart.
        func note(_ part: BackingPart, _ pitch: Pitch, _ velocity: Int, tick: Int, ticks: Int, held: Double = 0.9)
            -> BackingNote {
            let time = time(ofTick: first + tick)
            return BackingNote(part: part, pitch: pitch, velocity: velocity, time: time,
                               length: (self.time(ofTick: first + tick + ticks) - time) * held)
        }
        let beats = 0..<Self.beatsPerBar
        let root = triad.root.pitchClass.lowestPitch(atOrAbove: Self.bassLowest)
        let voicing = triad.pitchClasses.map { $0.lowestPitch(atOrAbove: Self.keysLowest) }
        /// The keys' chord on beats 1 and 3, held to the next.
        let halfBarKeys = [0, 2].flatMap { beat in
            voicing.map { note(.keys, $0, 70, tick: beat * Self.ticksPerBeat, ticks: 2 * Self.ticksPerBeat) }
        }
        /// Kick on 1 and 3, snare on 2 and 4.
        let backbeat = beats.map { beat in
            note(.drums, beat.isMultiple(of: 2) ? Drum.kick : Drum.snare, beat.isMultiple(of: 2) ? 110 : 100,
                 tick: beat * Self.ticksPerBeat, ticks: Self.ticksPerEighth)
        }
        switch style {
        case .rock:
            let eighths = 0..<(Self.ticksPerBar / Self.ticksPerEighth)
            let hiHats = eighths.map { eighth in
                note(.drums, Drum.closedHiHat, eighth.isMultiple(of: 2) ? 80 : 60,
                     tick: eighth * Self.ticksPerEighth, ticks: Self.ticksPerEighth)
            }
            let bass = eighths.map { eighth in
                note(.bass, root, eighth.isMultiple(of: 2) ? 100 : 85, tick: eighth * Self.ticksPerEighth,
                     ticks: Self.ticksPerEighth)
            }
            return backbeat + hiHats + bass + halfBarKeys
        case .popBallad:
            let drums = [note(.drums, Drum.kick, 100, tick: 0, ticks: Self.ticksPerEighth),
                         note(.drums, Drum.snare, 90, tick: 2 * Self.ticksPerBeat, ticks: Self.ticksPerEighth)]
            let hiHats = beats.map { beat in
                note(.drums, Drum.closedHiHat, beat.isMultiple(of: 2) ? 65 : 50, tick: beat * Self.ticksPerBeat,
                     ticks: Self.ticksPerEighth)
            }
            let bass = [note(.bass, root, 95, tick: 0, ticks: 2 * Self.ticksPerBeat),
                        note(.bass, root + .perfectFifth, 85, tick: 2 * Self.ticksPerBeat, ticks: 2 * Self.ticksPerBeat)]
            let keys = voicing.map { note(.keys, $0, 60, tick: 0, ticks: Self.ticksPerBar, held: 0.97) }
            return drums + hiHats + bass + keys
        case .bluesShuffle:
            /// Each beat's pair of shuffled eighths: the long one on the beat, the short one late.
            func shuffled(_ beat: Int, _ make: (_ tick: Int, _ ticks: Int, _ isOnBeat: Bool) -> BackingNote) -> [BackingNote] {
                let tick = beat * Self.ticksPerBeat
                return [make(tick, Self.shuffledOffbeat, true),
                        make(tick + Self.shuffledOffbeat, Self.ticksPerBeat - Self.shuffledOffbeat, false)]
            }
            let hiHats = beats.flatMap { beat in
                shuffled(beat) { note(.drums, Drum.closedHiHat, $2 ? 80 : 55, tick: $0, ticks: $1) }
            }
            let walk = [Interval.unison, .perfectFifth, .majorSixth, .perfectFifth].map { root + $0 }
            let bass = beats.flatMap { beat in
                shuffled(beat) { note(.bass, walk[beat], $2 ? 100 : 80, tick: $0, ticks: $1) }
            }
            return backbeat + hiHats + bass + halfBarKeys
        }
    }

    /// E1, the bass's low E.
    private static let bassLowest = Pitch(28)
    /// G3: each chord tone is the lowest from here up, so the keys keep to the middle, out of the guitar triads' way
    /// as far as they can.
    private static let keysLowest = Pitch(55)
}
