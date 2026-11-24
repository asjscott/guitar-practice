import Testing
@testable import ListenCore

@Suite struct AudioInputStateTests {
    private static let interface = AudioInputDevice(uid: "a", name: "Interface", channelCount: 2)
    private static let mic = AudioInputDevice(uid: "b", name: "Microphone", channelCount: 1)
    private let ready = AudioInputState(permission: .granted, device: interface, devices: [interface, mic], isRunning: true)

    @Test func problemSaysWhyNothingCanBeHeard() {
        #expect(ready.problem == nil)
        var state = ready
        state.device = nil
        #expect(state.problem == .noInput)
        state.permission = .denied
        #expect(state.problem == .noAccess)
        state.permission = .undetermined
        #expect(state.problem == .accessNotGiven)
    }

    @Test func nothingIsLostWhenNothingChanges() {
        #expect(ready.lossNotice(after: ready) == nil)
    }

    @Test func choosingAnotherInputLosesNothing() {
        var state = ready
        state.device = Self.mic
        #expect(state.lossNotice(after: ready) == nil)
    }

    @Test func aMissingDeviceWasDisconnectedEvenIfAnotherStandsIn() {
        let state = AudioInputState(permission: .granted, device: Self.mic, devices: [Self.mic], isRunning: true)
        #expect(state.lossNotice(after: ready) == "Interface was disconnected.")
    }

    @Test func losingAccessComesBeforeTheStop() {
        let state = AudioInputState(permission: .denied, device: Self.interface, devices: ready.devices, isRunning: false)
        #expect(state.lossNotice(after: ready) == "Microphone access was turned off.")
    }

    @Test func stoppingIsNoticedOnceOnly() {
        var state = ready
        state.isRunning = false
        #expect(state.lossNotice(after: ready) == "The audio input stopped.")
        #expect(state.lossNotice(after: state) == nil)
    }
}
