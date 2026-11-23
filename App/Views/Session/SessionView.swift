import PracticeCore
import SwiftUI
import TheoryCore

/// The Session screen, S4: setup, then for each block a Ready card and the drill under a bar of the session's drills,
/// then a summary. Return starts and leaves the summary; Space goes on; S skips; R is up to the drill; P pauses and
/// resumes; Esc pauses and asks before ending. A listening screen; leaving it pauses the session, as do sleep and losing
/// the input. Follows the tuning and capo in Settings.
struct SessionView: View {
    let model: SessionViewModel

    @Environment(AudioInputService.self) private var audioInput
    @Environment(AppSoundOutput.self) private var soundOutput
    @Environment(AttemptLog.self) private var log
    @AppStorage("session.minutes") private var minutes = SessionSetup().minutes
    @AppStorage("session.naturalsOnly") private var naturalsOnly = true
    @AppStorage("session.range") private var range = SessionRange.first12

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Session")
            .onPlainKey(press)
            .typesNoteNames(isActive: model.takesNoteNames) { model.press($0) }
            .listensToAudioInput(model.audioConsumer)
            .onAppear {
                model.log = log
                model.soundOutput = soundOutput
            }
            .onDisappear { model.leave() }
            .followsInstrumentSettings { tuning, capo in
                model.tuning = tuning
                model.capo = capo
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
                model.pause(notice: "The Mac went to sleep.")
            }
            .onChange(of: InputInUse(audioInput)) { old, new in
                if let notice = new.notice(after: old, in: audioInput.devices) { model.pause(notice: notice) }
            }
            .onChange(of: setup, initial: true) { model.setup = setup }
    }

    @ViewBuilder private var content: some View {
        switch model.stage {
        case .idle:
            SessionSetupView(minutes: $minutes, naturalsOnly: $naturalsOnly, range: $range, blocks: model.plan(),
                             problem: problem, start: start)
        case .ready, .playing, .paused:
            SessionPlayingView(model: model, inputProblem: inputProblem, resume: resume)
        case .finished:
            if let summary = model.summary {
                SessionSummaryView(summary: summary, tuning: model.fretboard.tuning, done: model.done)
            }
        }
    }

    private var setup: SessionSetup {
        SessionSetup(minutes: minutes, notes: naturalsOnly ? .naturals : .all, range: range)
    }

    /// Why a session can't start; nil when it can.
    private var problem: SessionProblem? {
        inputProblem ?? model.nothingToPromptReason.map(SessionProblem.nothingToPrompt)
    }

    /// Why nothing can be heard: a session can't start or resume. Nil when it can.
    private var inputProblem: SessionProblem? {
        if audioInput.permission == .denied { return .noAccess }
        return audioInput.canListen ? nil : .noInput
    }

    private func start() {
        if problem == nil { model.start() }
    }

    private func resume() {
        if inputProblem == nil { model.resume() }
    }

    private func press(_ key: PlainKey) -> Bool {
        switch (key, model.stage) {
        case (.return, .idle): start()
        case (.return, .finished): model.done()
        case (.space, .ready), (.space, .playing): model.next()
        case (.character("s"), .playing): model.skip()
        case (.character("r"), .playing): model.repeatPrompt()
        case (.character("p"), .ready), (.character("p"), .playing): model.pause()
        case (.character("p"), .paused): resume()
        case (.escape, .ready), (.escape, .playing): model.askToEnd()
        case (.escape, .paused): model.asksToEnd ? model.cancelEnd() : model.askToEnd()
        case (.return, .paused) where model.asksToEnd: model.end()
        default: return false
        }
        return true
    }
}

/// The input being listened to, to notice its loss.
private struct InputInUse: Equatable {
    let device: AudioInputDevice?
    let isRunning: Bool

    @MainActor init(_ audioInput: AudioInputService) {
        device = audioInput.choice?.device
        isRunning = audioInput.isRunning
    }

    /// Says how the input was lost, if it was. Choosing another input in Settings doesn't lose one.
    func notice(after old: InputInUse, in devices: [AudioInputDevice]) -> String? {
        if let lost = old.device, !devices.contains(where: { $0.uid == lost.uid }) { return "\(lost.name) was disconnected." }
        return old.isRunning && !isRunning ? "The audio input stopped." : nil
    }
}

#Preview {
    SessionView(model: SessionViewModel())
        .environment(AudioInputService(isInert: true))
        .environment(AppSoundOutput(isInert: true))
        .environment(AttemptLog.inMemory())
        .frame(width: 1100, height: 620)
}
