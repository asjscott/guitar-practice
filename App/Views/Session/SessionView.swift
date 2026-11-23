import PracticeCore
import SwiftUI
import TheoryCore

/// The Session screen, S4: setup, then for each block a Ready card and the drill under a bar of the session's drills,
/// then a summary. Return starts and leaves the summary; Space goes on; S skips; R is up to the drill. A listening
/// screen; leaving it ends the session. Follows the tuning and capo in Settings.
struct SessionView: View {
    let model: SessionViewModel

    @Environment(AudioInputService.self) private var audioInput
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
            .onAppear { model.log = log }
            .onDisappear { model.leave() }
            .followsInstrumentSettings { tuning, capo in
                model.tuning = tuning
                model.capo = capo
            }
            .onChange(of: setup, initial: true) { model.setup = setup }
    }

    @ViewBuilder private var content: some View {
        switch model.stage {
        case .idle:
            SessionSetupView(minutes: $minutes, naturalsOnly: $naturalsOnly, range: $range, blocks: model.plan(),
                             problem: problem, start: start)
        case .ready, .playing:
            SessionPlayingView(model: model)
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
        if audioInput.permission == .denied { return .noAccess }
        if !audioInput.canListen { return .noInput }
        return model.nothingToPromptReason.map(SessionProblem.nothingToPrompt)
    }

    private func start() {
        if problem == nil { model.start() }
    }

    private func press(_ key: PlainKey) -> Bool {
        switch (key, model.stage) {
        case (.return, .idle): start()
        case (.return, .finished): model.done()
        case (.space, .ready), (.space, .playing): model.next()
        case (.character("s"), .playing): model.skip()
        case (.character("r"), .playing): model.repeatPrompt()
        default: return false
        }
        return true
    }
}

#Preview {
    SessionView(model: SessionViewModel())
        .environment(AudioInputService(isInert: true))
        .environment(AttemptLog.inMemory())
        .frame(width: 1100, height: 620)
}
