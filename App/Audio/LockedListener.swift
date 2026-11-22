import ListenCore
import os

/// A ListenCore listener behind a lock, so a screen can run it on the audio tap's thread and reset it from the
/// main actor. A block that starts a new stream (after a device or format change) resets it first.
final class LockedListener: Sendable {
    private let listener = OSAllocatedUnfairLock(initialState: Listener())

    /// Runs one block of samples through the listener.
    func process(_ block: AudioInputBlock) -> ListenerOutput {
        listener.withLock { listener in
            if block.startsNewStream { listener = Listener() }
            return listener.process(block.samples, sampleRate: block.sampleRate, time: block.streamTime)
        }
    }

    /// Forgets everything the listener was tracking.
    func reset() {
        listener.withLock { $0 = Listener() }
    }
}
