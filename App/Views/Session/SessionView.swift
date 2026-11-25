import PracticeCore
import SwiftUI
import TheoryCore

/// The Session screen, S4: setup, then for each block a Ready card and the drill under a bar of the session's drills,
/// then a summary. Return starts and leaves the summary; Space goes on; S skips; + extends; R is up to the drill; in a scale block H shows the position and M opens the metronome panel; P pauses and
/// resumes; Esc pauses and asks before ending. A listening screen; leaving it pauses the session, as do sleep and losing
/// the input. Follows the tuning, capo and position system in Settings.
struct SessionView: View {
    let model: SessionViewModel

    @Environment(AppSoundOutput.self) private var soundOutput
    @Environment(Metronome.self) private var metronome
    @Environment(AttemptLog.self) private var log
    @AppStorage("session.minutes") private var minutes = SessionSetup().minutes
    @AppStorage("session.naturalsOnly") private var naturalsOnly = true
    @AppStorage("session.range") private var range = SessionRange.first12
    @AppStorage(InstrumentSettings.Key.positionSystem) private var positionSystem = InstrumentSettings.defaultPositionSystem

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Session")
            .onPlainKey(press)
            .holdsHint(isActive: model.takesHint) { model.hint(isShown: $0) }
            .typesNoteNames(isActive: model.takesNoteNames) { model.press($0) }
            .listensToAudioInput(model.audioConsumer)
            .onAppear {
                model.log = log
                model.soundOutput = soundOutput
                model.metronome = metronome
            }
            .onDisappear { model.leave() }
            .followsInstrumentSettings { tuning, capo in
                model.tuning = tuning
                model.capo = capo
            }
            .onChange(of: positionSystem, initial: true) { model.positionSystem = positionSystem }
            .onChange(of: soundOutput.problem) { model.soundChanged() }
            .noticesInterruptions(input: model.inputChanged, sleep: model.pause(notice:))
            .onChange(of: meters.meter, initial: true) { model.meter = meters.meter }
            .onChange(of: setup, initial: true) { model.setup = setup }
            // After the changes above, so that the first theme is picked for the neck in Settings.
            .task(id: model.themeNeck) { model.showTheme() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
                model.showTheme()
            }
    }

    @ViewBuilder private var content: some View {
        switch model.stage {
        case .idle:
            SessionSetupView(minutes: $minutes, naturalsOnly: $naturalsOnly, range: $range, theme: model.theme,
                             reroll: model.canReroll ? { model.reroll() } : nil, blocks: model.plan(), problem: model.problem,
                             noSoundNotice: model.noSoundNotice,
                             start: { model.start() })
        case .ready, .playing, .paused:
            SessionPlayingView(model: model)
        case .finished:
            if let summary = model.summary {
                SessionSummaryView(summary: summary, tuning: model.fretboard.tuning, key: model.theme?.key,
                                   done: model.done)
            }
        }
    }

    private let meters = StoredMeters()

    private var setup: SessionSetup {
        SessionSetup(minutes: minutes, notes: naturalsOnly ? .naturals : .all, range: range)
    }

    private func press(_ key: PlainKey) -> Bool {
        // The panel has its own.
        if model.isPanelOpen { return false }
        switch (key, model.stage) {
        case (.return, .idle): model.start()
        case (.return, .finished): model.done()
        case (.space, .ready), (.space, .playing): model.next()
        case (.character("s"), .playing): model.skip()
        case (.character("r"), .playing): model.repeatPrompt()
        // = is + without Shift.
        case (.character("+"), .playing), (.character("="), .playing): model.extend()
        case (.character("p"), .ready), (.character("p"), .playing): model.pause()
        case (.character("p"), .paused): model.resume()
        case (.escape, .ready), (.escape, .playing): model.askToEnd()
        case (.escape, .paused): model.asksToEnd ? model.cancelEnd() : model.askToEnd()
        case (.return, .paused) where model.asksToEnd: model.end()
        default: return false
        }
        return true
    }
}

#Preview {
    SessionView(model: SessionViewModel())
        .environment(AudioInputService(isInert: true))
        .environment(AppSoundOutput(isInert: true))
        .environment(Metronome(output: AppSoundOutput(isInert: true)))
        .environment(AttemptLog.inMemory())
        .frame(width: 1100, height: 620)
}
