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

    /// Listen's progression and tempo: I–V–vi–IV in G, 70 BPM. Its style is the progression's, as chosen in Settings
    /// or free practice.
    static let listenProgression = Progression.named("I–V–vi–IV")!
    static let listenKey = Key.major(.g)
    static let listenChords = listenProgression.chords(in: listenKey).map { BackingChord($0) }
    static let listenBPM = 70

    @ObservationIgnored private var backing: Backing?
    /// Notes before this have been handed to the output.
    @ObservationIgnored private var scheduledUntil: Duration = .zero
    /// No note is heard at or after this; nil = none set.
    @ObservationIgnored private var endsAt: Duration?
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
        endsAt = nil
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

    /// No note heard at or after a time; until then the backing goes on. A start replaces it.
    func end(at time: Duration) {
        guard isRunning else { return }
        endsAt = time
        output.cancelBacking(from: time)
    }

    /// Hands the output the next second's notes.
    private func playOn() {
        guard let backing else { return }
        var until = Metronome.now + Self.ahead
        if let endsAt { until = min(until, endsAt) }
        guard until > scheduledUntil else { return }
        output.schedule(backing.notes(from: scheduledUntil, before: until))
        scheduledUntil = until
    }

    // MARK: - Listen

    /// Plays Listen's progression in a style, with the metronome's click on top if asked, so that the two can be heard
    /// landing together. Does nothing while a drill has the click or the backing, or without the sounds.
    func listen(style: BackingStyle, withClick: Bool) {
        guard hasSounds, isListening || !isRunning, !metronome.isRunning || metronome.isListening || hasClick else { return }
        if hasClick { metronome.stop() }
        metronome.stopListening()
        var start = readyOutput()
        if withClick {
            let emphasis = metronome.meter.signature == .fourFour ? metronome.meter.emphasis : nil
            let track = ClickTrack(meter: Meter(.fourFour, emphasis: emphasis), bpm: Self.listenBPM, start: start)
            start = metronome.start(track).start
        }
        self.start(Backing(chords: Self.listenChords, style: style, bpm: Self.listenBPM, start: start))
        hasClick = withClick
        isListening = true
    }

    func stopListening() {
        if isListening { stop() }
    }
}

extension BackingPlayer {
    /// Does what a drill asks of the backing, in order, answering each start with the backing as it will be heard: on
    /// the player with its sounds, or without them (or a player), its beats as clicks on the metronome. Neither (in
    /// `LogCheck`) is heard as asked.
    static func perform(_ requests: [BackingRequest], on player: BackingPlayer?, metronome: Metronome?,
                        heard: (Backing) -> Void) {
        let hasSounds = player?.hasSounds == true
        for request in requests {
            switch request {
            case .start(let backing):
                if let player, hasSounds {
                    metronome?.stop()
                    heard(player.start(backing))
                } else if let metronome {
                    let clicks = metronome.start(ClickTrack(meter: Meter(.fourFour), bpm: backing.bpm, start: backing.start))
                    heard(Backing(chords: backing.chords, style: backing.style, bpm: backing.bpm, start: clicks.start))
                } else {
                    heard(backing)
                }
            case .end(let time):
                if hasSounds { player?.end(at: time) } else { metronome?.stop(at: time) }
            case .stop:
                player?.stop()
                metronome?.stop()
            }
        }
    }
}
