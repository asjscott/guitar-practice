import Foundation
import Observation
import PracticeCore
import TheoryCore

/// The app's one backing player: plays a `Backing` on the app's sound output, on the click clock (ADR 0006).
///
/// Every time here is when a note is heard, on the clock of `AudioInputService.hostTimeNow()`, as for `Metronome`.
/// Notes are handed to the output about a second ahead, each at its own time; the output sends them on to its samplers
/// just before they are due, so that stopping is prompt. With no output, or no sounds, the backing still goes on in
/// time, unheard. Losing the output is for whoever started it to notice (`AppSoundOutput.problem`).
@MainActor @Observable
final class BackingPlayer {
    /// Whether backing is going, or about to.
    private(set) var isRunning = false

    /// Whether it was started by Listen in Settings.
    private(set) var isListening = false

    /// Listen's progression, style and tempo: I–V–vi–IV in G, rock, 70 BPM.
    static let listenChords = [Triad(.major, root: .g), Triad(.major, root: .d), Triad(.minor, root: .e), Triad(.major, root: .c)]
        .map { BackingChord($0) }
    static let listenStyle = BackingStyle.rock
    static let listenBPM = 70

    @ObservationIgnored private var backing: Backing?
    /// Notes before this have been handed to the output.
    @ObservationIgnored private var scheduledUntil: Duration = .zero
    @ObservationIgnored private let output: AppSoundOutput
    @ObservationIgnored private let metronome: Metronome
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Whether Listen started the metronome too.
    @ObservationIgnored private var hasClick = false

    private static let ahead: Duration = .seconds(1)
    private static let interval: Duration = .milliseconds(200)
    /// The least time from asking for backing to its first note being sent to the output.
    private static let lead: Duration = .milliseconds(80)

    init(output: AppSoundOutput, metronome: Metronome) {
        self.output = output
        self.metronome = metronome
    }

    /// Whether the sounds have been fetched.
    var hasSounds: Bool { output.backingSoundFont != nil }

    /// Readies the output for backing, and returns the soonest a backing can start: its first note can't be heard
    /// sooner.
    private func readyOutput() -> Duration {
        let latency = output.startBacking() ?? .zero
        return Metronome.now + latency + Self.lead
    }

    /// Plays a backing from its count-in on, in place of any other, until stopped. Returns it as it will be heard:
    /// later than asked if its start is too soon to play.
    @discardableResult
    func start(_ backing: Backing) -> Backing {
        isListening = false
        stopNotes()
        let heard = Backing(chords: backing.chords, style: backing.style, bpm: backing.bpm,
                            start: max(backing.start, readyOutput()))
        self.backing = heard
        scheduledUntil = heard.start
        isRunning = true
        playOn()
        if task == nil {
            task = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.interval)
                    if !Task.isCancelled { self?.playOn() }
                }
            }
        }
        return heard
    }

    func stop() {
        guard isRunning else { return }
        task?.cancel()
        task = nil
        stopNotes()
        backing = nil
        output.endBacking()
        if hasClick { metronome.stop() }
        hasClick = false
        isRunning = false
        isListening = false
    }

    private func stopNotes() {
        output.cancelBacking(from: Metronome.now)
    }

    /// Hands the output the next second's notes.
    private func playOn() {
        guard let backing else { return }
        let until = Metronome.now + Self.ahead
        guard until > scheduledUntil else { return }
        output.schedule(backing.notes(from: scheduledUntil, before: until))
        scheduledUntil = until
    }

    // MARK: - Listen

    /// Plays Listen's progression, with the metronome's click on top if asked, so that the two can be heard landing
    /// together. Does nothing while a drill has the click or the backing, or without the sounds.
    func listen(withClick: Bool) {
        guard hasSounds, isListening || !isRunning, !metronome.isRunning || metronome.isListening || hasClick else { return }
        if hasClick { metronome.stop() }
        metronome.stopListening()
        var start = readyOutput()
        if withClick {
            let emphasis = metronome.meter.signature == .fourFour ? metronome.meter.emphasis : nil
            let track = ClickTrack(meter: Meter(.fourFour, emphasis: emphasis), bpm: Self.listenBPM, start: start)
            start = metronome.start(track).start
        }
        self.start(Backing(chords: Self.listenChords, style: Self.listenStyle, bpm: Self.listenBPM, start: start))
        hasClick = withClick
        isListening = true
    }

    func stopListening() {
        if isListening { stop() }
    }
}
