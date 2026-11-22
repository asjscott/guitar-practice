import Foundation

/// Turns raw (unsmoothed) pitch estimates and onsets into played notes.
///
/// A note counts once the estimates since its onset have held within a
/// narrow band for `PlayedNote.stability` and sit within
/// `PlayedNote.maximumCents` of an equal-tempered pitch. Then the tracker
/// waits: the next played note needs silence or a new onset.
struct NoteTracker: Sendable {
    /// Estimates further than this from the first of a run break the run, in octaves.
    private let band = 0.2 / 12
    /// How much of an analysis window may come from before the onset.
    private let windowOverlap: Double

    private var onset: Double?
    private var reported = false
    private var run: [Double] = []          // log2 of frequency
    private var runStart = 0.0             // end of the run's first window
    private var runFirstWindowStart = 0.0

    /// - Parameter windowDuration: length of the analysis window, in seconds.
    init(windowDuration: Double) {
        windowOverlap = windowDuration / 4
    }

    /// A new onset: a new played note may follow.
    mutating func onsetDetected(at time: Double) {
        onset = time
        reported = false
        run.removeAll()
    }

    /// The signal fell below the gate: a new played note may follow.
    mutating func silence() {
        onset = nil
        reported = false
        run.removeAll()
    }

    /// A window above the gate with no clear pitch: stability starts again.
    mutating func noPitch() {
        run.removeAll()
    }

    /// A pitch estimate for the window from `start` to `end` (stream seconds).
    /// Returns the played note if this estimate completes one.
    mutating func estimate(frequency: Double, start: Double, end: Double) -> PlayedNote? {
        guard !reported else { return nil }
        // Windows mostly from before the onset hear the previous sound.
        if let onset, start < onset - windowOverlap { return nil }
        let value = log2(frequency)
        if let first = run.first, abs(value - first) > band { run.removeAll() }
        if run.isEmpty { runStart = end; runFirstWindowStart = start }
        run.append(value)
        guard end - runStart >= PlayedNote.stability else { return nil }

        let sorted = run.sorted()
        let median = sorted[sorted.count / 2]
        let exact = 69 + 12 * (median - log2(440))
        let nearest = exact.rounded()
        let cents = (exact - nearest) * 100
        guard abs(cents) <= PlayedNote.maximumCents else { return nil }
        reported = true
        return PlayedNote(midiNote: Int(nearest), cents: cents, onset: onset ?? runFirstWindowStart)
    }
}
