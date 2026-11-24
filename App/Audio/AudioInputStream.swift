import Foundation
import ListenCore
import os

/// One block of mono samples from the chosen input channel, as delivered to a consumer.
struct AudioInputBlock: Sendable {
    var samples: [Float]
    /// Hz; can change when the input unit restarts (new device), so read it on every block.
    var sampleRate: Double
    /// Seconds from the start of this stream to the block's first sample, counted in samples (sample-accurate).
    /// Dropped audio leaves a gap. Restarts at 0 whenever the input unit restarts; see `startsNewStream`.
    var streamTime: Double
    /// Host time of the block's first sample in seconds, on the clock of `AudioInputService.hostTimeNow()`.
    /// Use it to compare audio events with UI events (e.g. when a prompt appeared). Nil if Core Audio gave none.
    var hostTime: Double?
    /// True for the first block after the input unit (re)starts (device change, reconfiguration, or the first
    /// listening screen opening): stream time restarts and the sample rate may differ. Reset per-stream state.
    var startsNewStream: Bool
}

/// Receives the chosen channel's samples. Called on the audio input thread, never the main actor, one block
/// at a time in order. Keep it quick and non-blocking: copy into your own state and hop to the main actor
/// for anything the UI shows.
typealias AudioInputConsumer = @Sendable (AudioInputBlock) -> Void

/// The consumers currently attached, shared between the main actor (attach/detach) and the audio input thread (deliver).
final class AudioInputConsumers: Sendable {
    private let consumers = OSAllocatedUnfairLock(initialState: [UUID: AudioInputConsumer]())

    func set(_ consumer: AudioInputConsumer?, for id: UUID) {
        consumers.withLock { $0[id] = consumer }
    }

    func deliver(_ block: AudioInputBlock) {
        let current = consumers.withLock { Array($0.values) }   // call outside the lock
        for consumer in current { consumer(block) }
    }
}

/// The input meter's newest level: a 0–1 fraction, and the stream time of the end of its block.
struct AudioInputLevel: Sendable {
    var fraction: Double
    var time: Double
}

/// What runs on the audio input thread for one run of the input unit: hands each block to the consumers and its
/// peak to the meter. Holds no main-actor state.
final class AudioInputStream: Sendable {
    /// One per block; the newest wins if the main actor falls behind.
    let levels: AsyncStream<AudioInputLevel>
    private let levelSink: AsyncStream<AudioInputLevel>.Continuation
    private let consumers: AudioInputConsumers

    init(consumers: AudioInputConsumers) {
        self.consumers = consumers
        (levels, levelSink) = AsyncStream.makeStream(of: AudioInputLevel.self, bufferingPolicy: .bufferingNewest(1))
    }

    func process(_ block: AudioInputBlock) {
        consumers.deliver(block)
        let peak = block.samples.withUnsafeBufferPointer(InputMeterScale.peakDBFS)
        levelSink.yield(AudioInputLevel(fraction: InputMeterScale.fraction(dBFS: peak),
                                        time: block.streamTime + Double(block.samples.count) / block.sampleRate))
    }

    func finish() { levelSink.finish() }
}
