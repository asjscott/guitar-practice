import AudioToolbox
import AVFoundation
import os

/// The device and format an input unit listens to: compared to tell a real change from a repeat notice.
struct InputSetup: Equatable, Sendable {
    var deviceID: AudioDeviceID
    var sampleRate: Double
    var channelCount: Int

    init(deviceID: AudioDeviceID) {
        self.deviceID = deviceID
        sampleRate = CoreAudioDevices.sampleRate(of: deviceID)
        channelCount = CoreAudioDevices.inputChannelCount(of: deviceID)
    }
}

/// An input-only Core Audio unit (AUHAL) on one device. AVAudioEngine's tap gives 100 ms blocks whatever size is
/// asked for; this gives the device's own IO blocks (ADR 0004).
///
/// Two threads: Core Audio's real-time thread only copies the chosen channel into a ring of blocks, and the audio
/// input thread takes them out and calls `onBlock`, so consumers may lock and allocate.
@MainActor
final class AudioInputUnit {
    private let unit: AudioUnit
    private let ring: AudioInputRing
    private let callbackRing: Unmanaged<AudioInputRing>
    private var isStopped = false

    /// Starts at once. `onBlock` is called on the audio input thread.
    init(setup: InputSetup, deviceName: String, channelIndex: Int, bufferFrames: UInt32,
         onBlock: @escaping AudioInputConsumer) throws(AudioInputError) {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        var newUnit: AudioUnit?
        guard let component = AudioComponentFindNext(nil, &description),
              AudioComponentInstanceNew(component, &newUnit) == noErr, let unit = newUnit else { throw .noInputUnit }

        // Input is element 1, output element 0.
        func set<Value>(_ property: AudioUnitPropertyID, _ scope: AudioUnitScope, _ element: AudioUnitElement,
                        _ value: Value) -> OSStatus {
            withUnsafePointer(to: value) {
                AudioUnitSetProperty(unit, property, scope, element, $0, UInt32(MemoryLayout<Value>.size))
            }
        }
        func failed(_ error: AudioInputError) -> AudioInputError {
            AudioComponentInstanceDispose(unit)
            return error
        }

        var status = set(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, UInt32(1))
        if status == noErr { status = set(kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, UInt32(0)) }
        if status == noErr { status = set(kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, setup.deviceID) }
        guard status == noErr else { throw failed(.couldNotSelectDevice(deviceName, status)) }

        CoreAudioDevices.setBufferFrames(bufferFrames, of: setup.deviceID)
        // One buffer per channel. The unit doesn't convert sample rates on input, so keep the device's.
        let format = AudioStreamBasicDescription(
            mSampleRate: setup.sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: UInt32(setup.channelCount), mBitsPerChannel: 32, mReserved: 0)
        // Every device's largest IO block, should the device not take the size asked for.
        let maxFrames: UInt32 = 4096
        let ring = AudioInputRing(unit: unit, setup: setup, channelIndex: min(channelIndex, setup.channelCount - 1),
                                  maxFrames: Int(maxFrames))
        let callbackRing = Unmanaged.passRetained(ring)
        let callback = AURenderCallbackStruct(inputProc: audioInputCallback, inputProcRefCon: callbackRing.toOpaque())

        status = set(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, format)
        if status == noErr { status = set(kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, maxFrames) }
        if status == noErr { status = set(kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, callback) }
        if status == noErr { status = AudioUnitInitialize(unit) }
        if status == noErr { status = AudioOutputUnitStart(unit) }
        guard status == noErr else {
            let error = failed(.couldNotStart(Int(status)))
            callbackRing.release()
            throw error
        }
        self.unit = unit
        self.ring = ring
        self.callbackRing = callbackRing
        ring.startThread(onBlock: onBlock)
    }

    /// Stops listening. No block is delivered after this returns.
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        callbackRing.release()      // the callback can't run any more
        ring.stopThread()
    }
}

/// Runs on Core Audio's real-time thread.
private let audioInputCallback: AURenderCallback = { context, flags, time, _, frames, _ in
    Unmanaged<AudioInputRing>.fromOpaque(context).takeUnretainedValue().capture(flags: flags, time: time, frames: frames)
}

/// Blocks on their way from the real-time thread (`capture`) to the audio input thread. All memory is allocated up
/// front. A slot belongs to the real-time thread until it is counted as written, then to the audio input thread
/// until it is counted as read; the lock covers the counts only.
private final class AudioInputRing: @unchecked Sendable {
    private struct Slot {
        var frames = 0
        var sampleTime = 0.0
        var hostTime: UInt64?
    }
    private struct Counts {
        var written = 0
        var read = 0
        var isStopping = false
    }

    private static let slotCount = 32
    private let unit: AudioUnit
    private let setup: InputSetup
    private let channelIndex: Int
    private let maxFrames: Int
    private let counts = OSAllocatedUnfairLock(initialState: Counts())
    private let slots = UnsafeMutablePointer<Slot>.allocate(capacity: slotCount)
    private let samples: UnsafeMutablePointer<Float>
    /// Where Core Audio writes all the channels, one after another.
    private let channels: UnsafeMutablePointer<Float>
    private let bufferList: UnsafeMutableAudioBufferListPointer
    private let blockReady = DispatchSemaphore(value: 0)
    private let threadEnded = DispatchSemaphore(value: 0)

    init(unit: AudioUnit, setup: InputSetup, channelIndex: Int, maxFrames: Int) {
        self.unit = unit
        self.setup = setup
        self.channelIndex = channelIndex
        self.maxFrames = maxFrames
        slots.initialize(repeating: Slot(), count: Self.slotCount)
        samples = .allocate(capacity: Self.slotCount * maxFrames)
        channels = .allocate(capacity: setup.channelCount * maxFrames)
        bufferList = AudioBufferList.allocate(maximumBuffers: setup.channelCount)
    }

    deinit {
        slots.deallocate()
        samples.deallocate()
        channels.deallocate()
        free(bufferList.unsafeMutablePointer)
    }

    /// Takes one block from the unit. Real-time: no allocation, and the lock is held only to read or add a count.
    /// If the audio input thread is a whole ring behind, the block is dropped and stream time shows a gap.
    func capture(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, time: UnsafePointer<AudioTimeStamp>,
                 frames: UInt32) -> OSStatus {
        let count = Int(frames)
        guard count > 0, count <= maxFrames else { return noErr }
        for index in 0..<bufferList.count {
            bufferList[index] = AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4,
                                            mData: channels + index * maxFrames)
        }
        let status = AudioUnitRender(unit, flags, time, 1, frames, bufferList.unsafeMutablePointer)
        guard status == noErr else { return status }

        let (written, isFull) = counts.withLock { ($0.written, $0.written - $0.read == Self.slotCount) }
        guard !isFull, let source = bufferList[channelIndex].mData else { return noErr }
        let slot = written % Self.slotCount
        memcpy(samples + slot * maxFrames, source, count * MemoryLayout<Float>.size)
        let stamp = time.pointee
        slots[slot] = Slot(frames: count, sampleTime: stamp.mSampleTime,
                           hostTime: stamp.mFlags.contains(.hostTimeValid) ? stamp.mHostTime : nil)
        counts.withLock { $0.written += 1 }
        blockReady.signal()
        return noErr
    }

    func startThread(onBlock: @escaping AudioInputConsumer) {
        let thread = Thread { [self] in
            deliver(to: onBlock)
            threadEnded.signal()
        }
        thread.name = "Audio input"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Waits for the block being delivered, if any; blocks not yet delivered are dropped.
    func stopThread() {
        counts.withLock { $0.isStopping = true }
        blockReady.signal()
        threadEnded.wait()
    }

    private func deliver(to onBlock: AudioInputConsumer) {
        var firstSampleTime: Double?
        while true {
            blockReady.wait()
            let (read, isEmpty, isStopping) = counts.withLock { ($0.read, $0.read == $0.written, $0.isStopping) }
            if isStopping { return }
            if isEmpty { continue }
            let index = read % Self.slotCount
            let slot = slots[index]
            let block = AudioInputBlock(
                samples: Array(UnsafeBufferPointer(start: samples + index * maxFrames, count: slot.frames)),
                sampleRate: setup.sampleRate,
                streamTime: (slot.sampleTime - (firstSampleTime ?? slot.sampleTime)) / setup.sampleRate,
                hostTime: slot.hostTime.map { AVAudioTime.seconds(forHostTime: $0) },
                startsNewStream: firstSampleTime == nil)
            if firstSampleTime == nil { firstSampleTime = slot.sampleTime }
            counts.withLock { $0.read += 1 }
            autoreleasepool { onBlock(block) }
        }
    }
}
