import Testing
@testable import ListenCore

@Suite struct AudioInputPlanTests {
    private func plan(listeners: Bool = true, permission: AudioInputPermission = .granted, choice: Bool = true,
                      changed: Bool = false, running: Bool = false, tried: Bool = false) -> AudioInputPlan {
        AudioInputPlan(hasListeners: listeners, permission: permission, hasChoice: choice, choiceChanged: changed,
                       isRunning: running, hasTriedToStart: tried)
    }

    @Test func startsWhenAListeningScreenOpens() {
        #expect(plan().unit == .restart)
    }

    @Test func leavesARunningUnitAlone() {
        #expect(plan(running: true, tried: true).unit == .leave)
    }

    @Test func restartsOnAnotherChoice() {
        #expect(plan(changed: true, running: true, tried: true).unit == .restart)
    }

    @Test func triesAgainAfterAFailedStart() {
        #expect(plan(tried: true).unit == .restart)
    }

    @Test func stopsWhenNoLongerWanted() {
        #expect(plan(listeners: false, running: true, tried: true).unit == .stop)
        #expect(plan(permission: .denied, running: true, tried: true).unit == .stop)
        #expect(plan(choice: false, running: true, tried: true).unit == .stop)
    }

    /// A failed start still watches its device, so it has something to stop.
    @Test func stopsAfterAFailedStart() {
        #expect(plan(listeners: false, tried: true).unit == .stop)
    }

    @Test func leavesAStoppedUnitAloneWhenNotWanted() {
        #expect(plan(listeners: false, changed: true).unit == .leave)
        #expect(plan(permission: .denied).unit == .leave)
    }

    @Test func asksForAccessOnlyWhenListeningAndUnanswered() {
        #expect(plan(permission: .undetermined).asksForPermission)
        #expect(!plan(listeners: false, permission: .undetermined).asksForPermission)
        #expect(!plan(permission: .denied).asksForPermission)
        #expect(!plan().asksForPermission)
    }
}

@Suite struct InputSetupTests {
    private let setup = InputSetup(deviceID: 7, sampleRate: 48_000, channelCount: 2)

    /// #20: starting the input causes notices; restarting on them never ends.
    @Test func aRepeatNoticeDoesNotRestart() {
        #expect(!InputSetup.needsRestart(tried: setup, now: setup))
    }

    @Test func aRealChangeRestarts() {
        var now = setup
        now.sampleRate = 44_100
        #expect(InputSetup.needsRestart(tried: setup, now: now))
        now = setup
        now.channelCount = 0
        #expect(InputSetup.needsRestart(tried: setup, now: now))
    }

    @Test func aStoppedInputDoesNotRestart() {
        #expect(!InputSetup.needsRestart(tried: nil, now: setup))
    }

    @Test func needsChannelsAndARateToStart() {
        #expect(setup.canStart)
        #expect(!InputSetup(deviceID: 7, sampleRate: 0, channelCount: 2).canStart)
        #expect(!InputSetup(deviceID: 7, sampleRate: 48_000, channelCount: 0).canStart)
    }
}
