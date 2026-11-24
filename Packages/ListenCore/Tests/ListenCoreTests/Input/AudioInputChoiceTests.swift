import Testing
@testable import ListenCore

@Suite struct AudioInputChoiceTests {
    private let builtIn = AudioInputDevice(uid: "mic", name: "MacBook Microphone", channelCount: 1)
    private let interface = AudioInputDevice(uid: "scarlett", name: "Scarlett 2i2", channelCount: 2)

    private func resolve(_ uid: String, _ channel: Int = 1, devices: [AudioInputDevice]? = nil,
                         defaultUID: String? = "mic") -> AudioInputChoice? {
        AudioInputChoice.resolve(savedUID: uid, savedChannel: channel, devices: devices ?? [interface, builtIn],
                                 defaultUID: defaultUID)
    }

    @Test func usesTheSavedDeviceAndChannel() {
        #expect(resolve("scarlett", 2) == AudioInputChoice(device: interface, channel: 2, isFallback: false))
    }

    @Test func usesTheSystemDefaultWhenNothingIsSaved() {
        #expect(resolve("") == AudioInputChoice(device: builtIn, channel: 1, isFallback: false))
    }

    @Test func fallsBackToTheSystemDefaultWhenTheSavedDeviceIsMissing() {
        #expect(resolve("gone") == AudioInputChoice(device: builtIn, channel: 1, isFallback: true))
    }

    @Test(arguments: [nil, "unlisted"]) func usesTheFirstDeviceWithoutAListedDefault(defaultUID: String?) {
        #expect(resolve("", defaultUID: defaultUID)?.device == interface)
    }

    @Test func isNilWithoutDevices() {
        #expect(resolve("scarlett", devices: []) == nil)
    }

    @Test(arguments: [0, -1, 3]) func aChannelTheDeviceLacksBecomesInput1(channel: Int) {
        #expect(resolve("scarlett", channel)?.channel == 1)
    }

    @Test func aFallbackDeviceWithoutTheSavedChannelUsesInput1() {
        #expect(resolve("gone", 2) == AudioInputChoice(device: builtIn, channel: 1, isFallback: true))
    }

    @Test func aDeviceReportingNoChannelsUsesInput1() {
        let odd = AudioInputDevice(uid: "odd", name: "Odd", channelCount: 0)
        #expect(resolve("odd", 1, devices: [odd])?.channel == 1)
    }

    @Test func labelNamesDeviceAndInput() {
        #expect(resolve("scarlett", 2)?.label == "Scarlett 2i2 · Input 2")
    }

    @Test func onlyTheEngineAggregateIsTemporary() {
        #expect(AudioInputDevice.isTemporary(uid: "CADefaultDeviceAggregate-123-0"))
        #expect(!AudioInputDevice.isTemporary(uid: "scarlett"))
    }
}
