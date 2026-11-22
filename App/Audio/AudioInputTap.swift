import AVFoundation
import os

/// One block of mono samples from the chosen input channel, as delivered to a consumer.
struct AudioInputBlock: Sendable {
    var samples: [Float]
    /// Hz; can change when the engine restarts (new device), so read it on every block.
    var sampleRate: Double
    /// Seconds from the start of this stream to the block's first sample, counted in samples (sample-accurate).
    /// Restarts near 0 whenever the engine restarts; see `startsNewStream`.
    var streamTime: Double
    /// Host time of the block's first sample in seconds, on the clock of `AudioInputService.hostTimeNow()`.
    /// Use it to compare audio events with UI events (e.g. when a prompt appeared). Nil if Core Audio gave none.
    var hostTime: Double?
    /// True for the first block after the engine (re)starts (device change, reconfiguration, or the first
    /// listening screen opening): stream time restarts and the sample rate may differ. Reset per-stream state.
    var startsNewStream: Bool
}

/// Receives the chosen channel's samples. Called on the audio tap's thread, never the main actor, one block
/// at a time in order. Keep it quick and non-blocking: copy into your own state and hop to the main actor
/// for anything the UI shows.
typealias AudioInputConsumer = @Sendable (AudioInputBlock) -> Void

/// The consumers currently attached, shared between the main actor (attach/detach) and the tap thread (deliver).
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

/// What runs on the tap thread for one engine run: takes the chosen channel out of each buffer, hands the
/// mono block to the consumers and the block's peak to the meter. Holds no main-actor state.
final class AudioInputTap: Sendable {
    /// Meter fractions (0–1), one per block; the newest wins if the main actor falls behind.
    let levels: AsyncStream<Double>
    private let levelSink: AsyncStream<Double>.Continuation
    private let channelIndex: Int
    private let consumers: AudioInputConsumers
    private let isFirstBlock = OSAllocatedUnfairLock(initialState: true)

    /// - Parameter channelIndex: 0-based channel to deliver (Input 1 = 0).
    init(channelIndex: Int, consumers: AudioInputConsumers) {
        self.channelIndex = channelIndex
        self.consumers = consumers
        (levels, levelSink) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))
    }

    /// Installs the tap on bus 0. Nonisolated on purpose: a closure formed here isn't main-actor isolated,
    /// so the audio thread calling it doesn't trip Swift's isolation check.
    nonisolated func install(on node: AVAudioInputNode, format: AVAudioFormat, bufferSize: AVAudioFrameCount) {
        node.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [self] buffer, time in
            process(buffer, at: time)
        }
    }

    func finish() { levelSink.finish() }

    private func process(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0, let data = buffer.floatChannelData else { return }
        let channel = min(channelIndex, channelCount - 1)

        let samples: [Float]
        if buffer.format.isInterleaved {
            let interleaved = data[0]
            samples = (0..<frames).map { interleaved[$0 * channelCount + channel] }
        } else {
            samples = Array(UnsafeBufferPointer(start: data[channel], count: frames))
        }

        let sampleRate = buffer.format.sampleRate
        let startsNewStream = isFirstBlock.withLock { first in defer { first = false }; return first }
        let block = AudioInputBlock(
            samples: samples,
            sampleRate: sampleRate,
            streamTime: time.isSampleTimeValid ? Double(time.sampleTime) / sampleRate : 0,
            hostTime: time.isHostTimeValid ? AVAudioTime.seconds(forHostTime: time.hostTime) : nil,
            startsNewStream: startsNewStream)

        consumers.deliver(block)
        let peak = samples.withUnsafeBufferPointer(InputMeterScale.peakDBFS)
        levelSink.yield(InputMeterScale.fraction(dBFS: peak))
    }
}
