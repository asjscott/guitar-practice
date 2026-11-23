import CoreAudio
import Foundation

/// Thin Core Audio queries: input devices, the system default input and output, UID → device ID, and change notices.
/// Hardware code, kept small and not unit-tested (spec #11, Testing Decisions).
enum CoreAudioDevices {
    /// Every device with at least one input channel, sorted by name. Output-only devices and the engine's
    /// temporary aggregate are left out.
    static func inputDevices() -> [AudioInputDevice] {
        allDeviceIDs().compactMap { id in
            let channels = inputChannelCount(of: id)
            guard channels > 0, let uid = string(kAudioDevicePropertyDeviceUID, of: id),
                  !AudioInputDevice.isTemporary(uid: uid) else { return nil }
            let name = string(kAudioObjectPropertyName, of: id) ?? uid
            return AudioInputDevice(uid: uid, name: name, channelCount: channels)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The UID of the system default input device, if there is one.
    static func defaultInputUID() -> String? {
        defaultID(kAudioHardwarePropertyDefaultInputDevice).flatMap { string(kAudioDevicePropertyDeviceUID, of: $0) }
    }

    /// The system default output device, if there is one.
    static func defaultOutputID() -> AudioDeviceID? { defaultID(kAudioHardwarePropertyDefaultOutputDevice) }

    private static func defaultID(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = globalAddress(selector)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    /// The current device ID for a UID (IDs change across reconnects; UIDs don't).
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { string(kAudioDevicePropertyDeviceUID, of: $0) == uid }
    }

    /// Calls `onChange` on the main queue whenever devices are added or removed or the default input changes.
    /// Keep the returned observer alive; release it to stop.
    static func observeChanges(_ onChange: @escaping @MainActor () -> Void) -> ChangeObserver {
        ChangeObserver(onChange)
    }

    /// Calls `onChange` on the main queue whenever a device's sample rate, streams or other set-up may have changed.
    /// Notices can repeat, or be caused by the app itself: check what really changed (`InputSetup`).
    static func observeChanges(of id: AudioDeviceID, _ onChange: @escaping @MainActor () -> Void) -> ChangeObserver {
        ChangeObserver(onChange, object: id, addresses: [
            globalAddress(kAudioDevicePropertyNominalSampleRate),
            globalAddress(kAudioDevicePropertyDeviceHasChanged),
            globalAddress(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput),
        ])
    }

    /// Calls `onChange` on the main queue whenever the default output changes.
    static func observeDefaultOutput(_ onChange: @escaping @MainActor () -> Void) -> ChangeObserver {
        ChangeObserver(onChange, addresses: [globalAddress(kAudioHardwarePropertyDefaultOutputDevice)])
    }

    /// Asks for an IO buffer of `frames`, kept within what the device allows. Applies to this app only.
    static func setBufferFrames(_ frames: UInt32, of id: AudioDeviceID) {
        var address = globalAddress(kAudioDevicePropertyBufferFrameSizeRange)
        var range = AudioValueRange()
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &range) == noErr else { return }
        var wanted = max(min(frames, UInt32(range.mMaximum)), UInt32(range.mMinimum))
        address.mSelector = kAudioDevicePropertyBufferFrameSize
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &wanted)
    }

    /// The device's sample rate in Hz; 0 if it has none.
    static func sampleRate(of id: AudioDeviceID) -> Double {
        var address = globalAddress(kAudioDevicePropertyNominalSampleRate)
        var rate = 0.0
        var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate) == noErr else { return 0 }
        return rate
    }

    final class ChangeObserver {
        private let listener: AudioObjectPropertyListenerBlock
        private let object: AudioObjectID
        private let addresses: [AudioObjectPropertyAddress]

        fileprivate init(_ onChange: @escaping @MainActor () -> Void,
                         object: AudioObjectID = AudioObjectID(kAudioObjectSystemObject),
                         addresses: [AudioObjectPropertyAddress] = [
                            globalAddress(kAudioHardwarePropertyDevices),
                            globalAddress(kAudioHardwarePropertyDefaultInputDevice),
                         ]) {
            // Delivered on the main queue (below), so assuming main-actor isolation is sound.
            listener = { _, _ in MainActor.assumeIsolated { onChange() } }
            self.object = object
            self.addresses = addresses
            for var address in addresses {
                AudioObjectAddPropertyListenerBlock(object, &address, .main, listener)
            }
        }

        deinit {
            for var address in addresses {
                AudioObjectRemovePropertyListenerBlock(object, &address, .main, listener)
            }
        }
    }

    // MARK: - Property helpers

    fileprivate static func globalAddress(_ selector: AudioObjectPropertySelector,
                                      scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = globalAddress(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// Total channels across the device's input streams.
    static func inputChannelCount(of id: AudioDeviceID) -> Int {
        var address = globalAddress(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, list) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ selector: AudioObjectPropertySelector, of id: AudioObjectID) -> String? {
        var address = globalAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
