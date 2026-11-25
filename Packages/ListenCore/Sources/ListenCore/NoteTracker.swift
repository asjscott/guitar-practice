import Foundation

/// Turns raw (unsmoothed) pitch estimates and onset candidates into played notes.
///
/// A pitch counts once the estimates since a candidate have held within a narrow band for `PlayedNote.stability` and
/// sit within `PlayedNote.maximumCents` of an equal-tempered pitch. Then the tracker decides which candidate the pitch
/// began at, and whether it is a new note or the last one ringing on through a click (ADR 0005).
struct NoteTracker: Sendable {
    /// Estimates further than this from the first of a run break the run, in octaves.
    private let band = 0.2 / 12
    /// How much of an analysis window may come from before the onset.
    private let windowOverlap: Double
    private let windowDuration: Double

    // Rules for a new note, in dB: how far the level rises across the candidate, measured once a click has died away,
    // and how far the highs jump. Where the numbers come from is in ADR 0005.
    /// The same pitch. A click over a steadily ringing recorded note makes 0.6 at most.
    private let samePitchRise = 1.5
    /// The highs' jump for the same pitch after less than a 3 dB jump.
    private let samePitchBrightness = 6.0
    /// Another pitch after less than a 3 dB jump. A hammer-on or pull-off doesn't rise so.
    private let newPitchRise = 2.0
    /// The same, by the highs' jump, alone and with the rise. The recorded hammer-ons come to 8 at most.
    private let pickBrightness = 9.0
    private let newPitchBrightness = 11.0
    /// How far a soft pluck may fall below the note before it.
    private let softest = 6.0
    /// Two notes of one pitch are at least this far apart; before that it is one attack building up.
    private let sameNoteSpacing = 0.1
    /// How long after a candidate a click may still be heard, in seconds.
    private let clickLength = 0.04
    /// How long a note that faded below the gate is remembered, in seconds.
    private let memory = 0.5

    private struct Sounding: Sendable {
        var midiNote: Int
        var frequency: Double
        let onset: Double
        var heardUntil: Double
    }

    private struct Level: Sendable {
        let start: Double, end: Double, decibels: Double
    }

    private var pending: [OnsetDetector.Candidate] = []
    /// Candidates of the last moments, dealt with or not.
    private var recent: [OnsetDetector.Candidate] = []
    private var afterSilence = true
    private var sounding: Sounding?
    private var levels: [Level] = []
    private var run: [Double] = []          // log2 of frequency
    private var following: [Double] = []    // the same, of the note ringing on
    private var runStart = 0.0             // end of the run's first window
    private var runFirstWindowStart = 0.0

    /// - Parameter windowDuration: length of the analysis window, in seconds.
    init(windowDuration: Double) {
        self.windowDuration = windowDuration
        windowOverlap = windowDuration / 4
    }

    /// A moment that may be an onset: a new played note may follow.
    mutating func candidate(_ candidate: OnsetDetector.Candidate) {
        if pending.isEmpty { run.removeAll(); following.removeAll() }
        pending.append(candidate)
        recent.append(candidate)
    }

    /// The level of every window, given before what was heard in it.
    mutating func level(_ decibels: Double, start: Double, end: Double) {
        levels.append(Level(start: start, end: end, decibels: decibels))
        if levels.count > 64 { levels.removeFirst(levels.count - 40) }
        // A candidate nothing came of.
        pending.removeAll { $0.time < start - 0.5 }
        recent.removeAll { $0.time < start - 0.5 }
    }

    /// The signal fell below the gate for this window: a new played note may follow.
    mutating func silence(start: Double, end: Double) {
        pending.removeAll { $0.time < start }
        run.removeAll()
        afterSilence = true
        if let sounding, end - sounding.heardUntil > memory { self.sounding = nil }
    }

    /// A window above the gate with no clear pitch: stability starts again.
    mutating func noPitch() {
        run.removeAll()
    }

    /// A pitch estimate for the window from `start` to `end` (stream seconds). `sound` is the low end of the recent
    /// sound. Returns the played note if this estimate completes one.
    mutating func estimate(frequency: Double, start: Double, end: Double, sound: LowSound, highs: Highs) -> PlayedNote? {
        let value = log2(frequency)
        if pending.isEmpty, !afterSilence { follow(value, end: end) }
        guard afterSilence || !pending.isEmpty else { return nil }
        // Windows mostly from before the first candidate hear the previous sound.
        if let first = pending.first, start < first.time - windowOverlap { return nil }
        if let first = run.first, abs(value - first) > band { run.removeAll() }
        if run.isEmpty { runStart = end; runFirstWindowStart = start }
        run.append(value)
        guard end - runStart >= PlayedNote.stability else { return nil }

        let median = run.sorted()[run.count / 2]
        let exact = 69 + 12 * (median - log2(440))
        let nearest = exact.rounded()
        let cents = (exact - nearest) * 100
        guard abs(cents) <= PlayedNote.maximumCents else { return nil }

        let midiNote = Int(nearest)
        // A loud note can be heard in a window it only fills the end of.
        let eligible = pending.filter { $0.time <= runStart - 0.1 * windowDuration }
        let chosen = began(pow(2, median), at: eligible, end: end, sound: sound)
        let isNew = isNew(midiNote, at: chosen, among: eligible, end: end, highs: highs)
        let note = PlayedNote(midiNote: midiNote, cents: cents, onset: chosen?.time ?? runFirstWindowStart)
        // These candidates are dealt with. Later ones are weighed up next, by later windows.
        pending.removeFirst(eligible.count)
        afterSilence = false
        run.removeAll()
        guard isNew else { return nil }
        sounding = Sounding(midiNote: midiNote, frequency: pow(2, median), onset: note.onset, heardUntil: end)
        return note
    }

    /// Follows the note ringing on, through any legato, so that a later click over it isn't a new note.
    private mutating func follow(_ value: Double, end: Double) {
        guard sounding != nil else { return }
        if let first = following.first, abs(value - first) > band { following.removeAll() }
        following.append(value)
        guard following.count >= 3 else { return }
        let frequency = pow(2, following.reduce(0, +) / Double(following.count))
        sounding?.frequency = frequency
        sounding?.midiNote = Int((69 + 12 * log2(frequency / 440)).rounded())
        sounding?.heardUntil = end
        if following.count > 8 { following.removeFirst(4) }
    }

    /// The candidate the pitch began at: the last one that it wasn't already sounding before.
    private func began(
        _ frequency: Double, at candidates: [OnsetDetector.Candidate], end: Double, sound: LowSound
    ) -> OnsetDetector.Candidate? {
        guard let first = candidates.first else { return nil }
        for (previous, candidate) in zip(candidates, candidates.dropFirst()).reversed() {
            let length = min(candidate.time - previous.time, 0.04)
            // Too short a stretch to tell one pitch from another.
            guard length >= max(0.5 / frequency, 0.004) else { continue }
            let stretch = (candidate.time - length)...candidate.time
            let match = sound.match(stretch, period: 1 / frequency, near: end - windowDuration / 2 - 0.1 / frequency)
            var ringing = 0.0
            if let sounding {
                ringing = sound.match(stretch, period: 1 / sounding.frequency, near: first.time - windowDuration / 2).similarity
            }
            if match.similarity < 0.8 || match.gain < 0.3 || match.similarity < ringing { return candidate }
        }
        return first
    }

    private func isNew(
        _ midiNote: Int, at candidate: OnsetDetector.Candidate?, among candidates: [OnsetDetector.Candidate], end: Double, highs: Highs
    ) -> Bool {
        guard let sounding else { return true }
        let interval = abs(midiNote - sounding.midiNote)
        // An octave or a twelfth up is a harmonic of a ringing note, which can outlast its fundamental.
        let isSamePitch = [0, 12, 19, 24].contains(interval)
        // No candidate: after silence, a sound that faded in, or the last note wavering about the gate.
        guard let candidate else { return !isSamePitch }
        // One attack can make several candidates.
        let attack = candidates.filter { $0.time >= candidate.time - 0.01 && $0.time <= candidate.time + 0.03 }
        let isStrong = attack.contains(where: \.isStrong)
        if isStrong, !isSamePitch { return true }
        if interval == 0, candidate.time - sounding.onset < sameNoteSpacing { return false }
        let rise = rise(across: candidate, among: candidates, end: end)
        // A click just before a pick hides the pick's highs, so its own jump counts for both.
        let jump = recent.filter { candidate.time - 0.06 ... candidate.time ~= $0.time }.map { highs.jump(at: $0.time) }.max() ?? 0
        // A click leaves the note's decay as it was.
        if isSamePitch { return rise >= samePitchRise && (isStrong || jump >= samePitchBrightness) }
        return rise >= newPitchRise || (rise >= -softest && jump >= pickBrightness && rise + jump >= newPitchBrightness)
    }

    /// How much louder the sound is after a candidate than its decay before would have left it, in dB.
    private func rise(across candidate: OnsetDetector.Candidate, among candidates: [OnsetDetector.Candidate], end: Double) -> Double {
        // Other candidates may be clicks, so windows they touch don't count if others will do.
        let others = recent.map(\.time).filter { $0 != candidate.time }
        func clear(_ windows: [Level]) -> [Level] {
            let clear = windows.filter { window in !others.contains { window.end > $0 && window.start < $0 + clickLength } }
            return clear.isEmpty ? windows : clear
        }
        let firstTime = min(candidates.map(\.time).filter { $0 > candidate.time - 0.1 }.min() ?? candidate.time, candidate.time)
        let before = clear(levels.filter { $0.end <= firstTime && $0.end > firstTime - 0.15 && $0.start >= (sounding?.onset ?? 0) })
        let after = clear(levels.filter { $0.start >= candidate.time + clickLength && $0.end <= end })
        guard let ringing = Self.level(before, at: candidate.time), let now = Self.level(after, at: candidate.time) else {
            return .infinity
        }
        // The steepest decay may be a finger stopping the string, so it can't make a rise by itself.
        return min(now - ringing, now - before[before.count - 1].decibels + 0.5)
    }

    /// The level at a time, by the decay of these windows.
    private static func level(_ levels: [Level], at time: Double) -> Double? {
        guard !levels.isEmpty else { return nil }
        let middles = levels.map { ($0.start + $0.end) / 2 }
        let count = Double(levels.count)
        let meanTime = middles.reduce(0, +) / count
        let mean = levels.reduce(0) { $0 + $1.decibels } / count
        let spread = middles.reduce(0) { $0 + ($1 - meanTime) * ($1 - meanTime) }
        guard spread > 0 else { return mean }
        let slope = zip(middles, levels).reduce(0) { $0 + ($1.0 - meanTime) * $1.1.decibels } / spread
        return mean + min(0, max(-40, slope)) * (time - meanTime)
    }
}
