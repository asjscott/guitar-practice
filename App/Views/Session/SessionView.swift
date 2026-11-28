import PracticeCore
import SwiftUI
import TheoryCore

/// The Session screen, layout C: the daily routine's rail down the left; setup, then for each step a Ready card and the
/// drill, then a summary. Return starts and leaves the summary; Space goes on; S skips; + extends; R is up to the drill; in a scale or triad block H shows what has faded, and in a scale block M opens the metronome panel; P pauses and
/// resumes; Esc pauses and asks before ending. A listening screen; leaving it pauses the session, as do sleep and losing
/// the input. Follows the tuning, capo and position system in Settings.
struct SessionView: View {
    let model: SessionViewModel

    @Environment(AppSoundOutput.self) private var soundOutput
    @Environment(Metronome.self) private var metronome
    @Environment(BackingPlayer.self) private var backingPlayer
    @Environment(AttemptLog.self) private var log
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
                model.backingPlayer = backingPlayer
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
            SessionSetupView(naturalsOnly: $naturalsOnly, range: $range, theme: model.theme,
                             reroll: model.canReroll ? { model.reroll() } : nil, steps: model.plannedSteps(),
                             estimate: model.estimateText(), problem: model.problem, noSoundNotice: model.noSoundNotice,
                             notices: model.notices, backingNotices: model.backingNotices, start: { model.start() })
        case .ready, .playing, .paused:
            SessionPlayingView(model: model)
        case .finished:
            if let summary = model.summary {
                SessionSummaryView(summary: summary, steps: model.snapshot.steps, tuning: model.fretboard.tuning,
                                   key: model.theme?.key, done: model.done)
            }
        }
    }

    private let meters = StoredMeters()

    private var setup: SessionSetup {
        SessionSetup(notes: naturalsOnly ? .naturals : .all, range: range)
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
        .environment(BackingPlayer(output: AppSoundOutput(isInert: true), metronome: Metronome(output: AppSoundOutput(isInert: true))))
        .environment(AttemptLog.inMemory())
        .frame(width: 1100, height: 620)
}
