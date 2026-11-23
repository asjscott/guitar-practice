import CoreAudio
import Foundation

/// Thin Core Audio queries: input devices, the system default input, UID → device ID, and change notices.
/// Hardware code, kept small and not unit-tested (spec #11, Testing Decisions).
enum CoreAudioDevices {
    /// Every device with at least one input channel, sorted by name. Output-only devices are left out.
    static func inputDevices() -> [AudioInputDevice] {
        allDeviceIDs().compactMap { id in
            let channels = inputChannelCount(of: id)
            guard channels > 0, let uid = string(kAudioDevicePropertyDeviceUID, of: id) else { return nil }
            let name = string(kAudioObjectPropertyName, of: id) ?? uid
            return AudioInputDevice(uid: uid, name: name, channelCount: channels)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The UID of the system default input device, if there is one.
    static func defaultInputUID() -> String? {
        var address = globalAddress(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return string(kAudioDevicePropertyDeviceUID, of: id)
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

    final class ChangeObserver {
        private let listener: AudioObjectPropertyListenerBlock
        private static let selectors = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice]

        fileprivate init(_ onChange: @escaping @MainActor () -> Void) {
            // Delivered on the main queue (below), so assuming main-actor isolation is sound.
            listener = { _, _ in MainActor.assumeIsolated { onChange() } }
            for selector in Self.selectors {
                var address = globalAddress(selector)
                AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
            }
        }

        deinit {
            for selector in Self.selectors {
                var address = globalAddress(selector)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
            }
        }
    }

    // MARK: - Property helpers

    private static func globalAddress(_ selector: AudioObjectPropertySelector,
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
    private static func inputChannelCount(of id: AudioDeviceID) -> Int {
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
