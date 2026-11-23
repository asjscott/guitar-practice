import ListenCore
import TheoryCore

/// A played note with its times on the host clock (`AudioInputService.hostTimeNow()`, in seconds): the drill clock.
struct HeardNote: Sendable {
    let pitch: Pitch
    let onset: Double
    let detected: Double
}

/// Turns audio input into played notes on the drill clock, for any screen that drives a drill.
final class PlayedNoteFeed: Sendable {
    private let listener = LockedListener()

    /// A consumer for `.listensToAudioInput(_:)`: runs the listener on the audio input thread and hands what it
    /// heard to `receive` on the main actor.
    func consumer(_ receive: @escaping @MainActor @Sendable ([HeardNote]) -> Void) -> AudioInputConsumer {
        let listener = self.listener
        return { block in
            let playedNotes = listener.process(block).playedNotes
            guard !playedNotes.isEmpty else { return }
            let clock = StreamClock(block: block)
            let heard = playedNotes.map {
                HeardNote(pitch: Pitch($0.midiNote), onset: clock.hostTime(ofStreamTime: $0.onset), detected: clock.blockEnd)
            }
            Task { @MainActor in receive(heard) }
        }
    }

    /// Forgets what the listener was tracking.
    func reset() { listener.reset() }
}

/// Moves stream times from one audio block onto the host clock that `AudioInputService.hostTimeNow()` uses.
private struct StreamClock {
    /// Host time minus stream time for this block.
    let offset: Double
    /// Host time of the end of the block: when its played notes were detected.
    let blockEnd: Double

    init(block: AudioInputBlock) {
        let streamEnd = block.streamTime + Double(block.samples.count) / block.sampleRate
        // Without a host time from Core Audio, take the block as just finished.
        offset = block.hostTime.map { $0 - block.streamTime } ?? (AudioInputService.hostTimeNow() - streamEnd)
        blockEnd = streamEnd + offset
    }

    func hostTime(ofStreamTime time: Double) -> Double { time + offset }
}
