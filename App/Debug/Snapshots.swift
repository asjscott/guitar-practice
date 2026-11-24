#if DEBUG
import AppKit
import ListenCore
import PracticeCore
import SwiftUI
import TheoryCore

/// Renders the app's screens to PNGs and quits, when `GP_SNAPSHOT=<dir>` is set (see `scripts/snapshot`).
///
/// Draws the app's own offscreen windows, native controls included, so it needs no screen-recording permission.
/// Audio input is inert, so it never asks for the microphone, and the attempt log is in memory. Add a `save` for each new screen or state.
/// Not faithful: window titles ("Untitled"), and toolbar buttons in dark mode (white blobs).
@MainActor
enum Snapshots {
    private static let environment = ProcessInfo.processInfo.environment
    private static let screenSize = CGSize(width: 1100, height: 620)
    private static let audioInput = AudioInputService(defaults: emptyDefaults, isInert: true)
    /// Nothing saved: default settings, and the audio line shows the system default rather than a fallback warning.
    private static let emptyDefaults = UserDefaults(suiteName: "GuitarPractice.snapshots") ?? .standard

    static var isRequested: Bool { environment["GP_SNAPSHOT"] != nil }

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: environment["GP_SNAPSHOT_APPEARANCE"] == "dark" ? .darkAqua : .aqua)
        Task {
            do {
                try await saveAll()
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data("Snapshot failed: \(error)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        app.run()
        exit(EXIT_FAILURE)
    }

    private static func saveAll() async throws {
        // PROTOTYPE: only the Phase 3 variants.
        for variant in ProtoVariant.allCases {
            for scene in ProtoScene.allCases {
                try await save("p3-\(variant.rawValue)-\(scene.rawValue)", ProtoScreen(model: ProtoModel(scene: scene, variant: variant), showsSwitcher: false))
            }
            for stage in [ProtoStage.faded, .hidden] {
                try await save("p3-\(variant.rawValue)-pass-\(stage.rawValue)", ProtoScreen(model: ProtoModel(scene: .pass, variant: variant, stage: stage), showsSwitcher: false))
            }
        }
        return
        try await save("explorer", ExplorerView(model: ExplorerViewModel()))

        let tuner = TunerViewModel()
        try await save("tuner-silent", TunerView(model: tuner))
        try await save("tuner-sounding", TunerView(model: tuner)) {
            tuner.show(TunerReading(frequency: 83.3))
        }

        let drill = DrillViewModel()
        try await save("drill-idle", DrillView(model: drill))
        drill.stop()
        try await save("drill-waiting", DrillView(model: drill)) { drill.start(seed: 1) }
        drill.stop()
        try await save("drill-wrong", DrillView(model: drill)) {
            drill.start(seed: 1)
            drill.playForSnapshot(right: false)
        }
        // Right answers advance after a short pause, so pause the run to hold the lit neck still.
        drill.stop()
        try await save("drill-correct", DrillView(model: drill), settle: .milliseconds(150)) {
            drill.start(seed: 1)
            drill.playForSnapshot(right: true)
        }

        drill.stop()
        try await save("drill-skipped", DrillView(model: drill)) {
            drill.start(seed: 1)
            drill.skip()
        }
        drill.stop()
        try await save("drill-paused", DrillView(model: drill)) {
            drill.start(seed: 1)
            drill.togglePause()
        }
        drill.stop()
        try await save("drill-paused-no-input", DrillView(model: drill)) {
            drill.start(seed: 1)
            drill.inputChanged(AudioInputState(permission: .granted, device: nil, devices: [], isRunning: false))
        }
        // Leaving paused it; coming back, the same run is there.
        try await save("drill-back-while-paused", DrillView(model: drill)) { precondition(drill.isPaused) }
        drill.stop()
        try await save("drill-access-asked", DrillView(model: drill)) {
            drill.inputChanged(AudioInputState(permission: .undetermined, device: nil, devices: [], isRunning: false))
        }
        drill.stop()
        try await save("drill-nothing-to-prompt", DrillView(model: drill)) {
            drill.tuning = TuningPreset.eFlatStandard.tuning
            drill.capo = 12
        }

        let hear = DrillViewModel()
        hear.kind = .hearFindIt
        hear.stop()
        try await save("hear-waiting", DrillView(model: hear)) { hear.start(seed: 1) }
        hear.stop()
        try await save("hear-wrong", DrillView(model: hear)) {
            hear.start(seed: 1)
            hear.playForSnapshot(right: false)
        }
        hear.stop()
        try await save("hear-correct", DrillView(model: hear), settle: .milliseconds(150)) {
            hear.start(seed: 1)
            hear.skip()
            hear.playForSnapshot(right: true)
        }
        hear.stop()
        try await save("hear-timed-out", DrillView(model: hear)) {
            hear.start(seed: 1)
            hear.timeOutForSnapshot()
        }
        let unheard = DrillViewModel()
        unheard.kind = .hearFindIt
        try await save("hear-no-output", DrillView(model: unheard),
                       sound: AppSoundOutput(isInert: true, problem: "There’s no sound output device."))

        let sweep = DrillViewModel()
        sweep.kind = .allInstances
        sweep.stop()
        try await save("drill-sweep", DrillView(model: sweep)) {
            sweep.start(seed: 1)
            sweep.playForSnapshot(right: true)
            sweep.playForSnapshot(right: true)
            sweep.skip()
            sweep.playForSnapshot(right: true)
        }
        sweep.stop()
        try await save("drill-sweep-wrong", DrillView(model: sweep)) {
            sweep.start(seed: 1)
            sweep.playForSnapshot(right: true)
            sweep.playForSnapshot(right: false)
        }
        sweep.stop()
        try await save("drill-sweep-paused", DrillView(model: sweep)) {
            sweep.start(seed: 1)
            sweep.togglePause()
        }

        // Typed with real key events, so the key handling is exercised too.
        let naming = DrillViewModel()
        naming.kind = .fretNameIt
        naming.stop()
        try await save("fret-name-it-waiting", DrillView(model: naming)) { naming.start(seed: 1) }
        naming.stop()
        try await save("fret-name-it-typed", DrillView(model: naming)) {
            naming.start(seed: 1)
            type("gb")
        }
        naming.stop()
        try await save("fret-name-it-wrong", DrillView(model: naming)) {
            naming.start(seed: 1)
            type("gb\r")
        }
        naming.stop()
        try await save("fret-name-it-right", DrillView(model: naming), settle: .milliseconds(150)) {
            naming.start(seed: 1)
            naming.answerForSnapshot()
        }
        naming.stop()
        try await save("fret-name-it-timed-out", DrillView(model: naming), settle: .milliseconds(10_800)) {
            naming.start(seed: 1)
        }

        try await save("drill-not-saving", DrillView(model: DrillViewModel()), log: .inMemory(problem: "The file couldn’t be opened."))

        try await saveSession()

        try await save("settings-instrument", InstrumentSettingsView(), size: CGSize(width: 520, height: 640))
        let activeSessions = ActiveSessions()
        activeSessions.set(UUID(), isActive: true)
        try await save("settings-instrument-locked", InstrumentSettingsView().environment(activeSessions),
                       size: CGSize(width: 520, height: 700))
        try await save("settings-audio", AudioSettingsView(), size: CGSize(width: 520, height: 480))
    }

    private static func saveSession() async throws {
        let problems: [(String, SessionProblem)] = [
            ("access", .input(.noAccess)), ("access-asked", .input(.accessNotGiven)), ("input", .input(.noInput)),
            ("prompts", .nothingToPrompt("No natural notes in these frets and strings. Choose All notes.")),
        ]
        for (name, problem) in problems {
            try await save("session-setup-no-\(name)", SessionSetupView(
                minutes: .constant(10), naturalsOnly: .constant(false), range: .constant(.wholeNeck),
                theme: SessionTheme(Theme(key: .minor(.dSharp), position: Position.ID(system: .threeNotesPerString, number: 2)),
                                    on: Fretboard(tuning: .standard)),
                reroll: nil, blocks: SessionViewModel().plan(), problem: problem, start: {}))
        }
        let session = SessionViewModel()
        try await save("session-setup", SessionView(model: session))

        let silent = AppSoundOutput(isInert: true, problem: "There’s no sound output device.")
        try await save("session-setup-no-sound", SessionView(model: SessionViewModel()), sound: silent)

        // The whole window, with its sidebar focused: Return and Space must get through by themselves.
        try await save("session-ready-by-keys", ContentView(), settle: .milliseconds(1600)) {
            focusSidebar()
            type("\r")
        }
        try await save("session-playing-by-keys", ContentView(), settle: .milliseconds(1600)) {
            focusSidebar()
            type("\r ")
        }

        /// A new session, playing the block of a drill.
        func play(_ kind: DrillKind) {
            session.done()
            session.end()
            session.done()
            session.start(seed: 1)
            session.next()
            while session.isActive, session.blockKind != kind {
                session.next()
                session.next()
            }
        }
        try await save("session-waiting", SessionView(model: session)) { play(.notePlayIt) }
        try await save("session-wrong", SessionView(model: session)) {
            play(.notePlayIt)
            session.answerForSnapshot(right: false)
        }
        try await save("session-right", SessionView(model: session), settle: .milliseconds(150)) {
            play(.notePlayIt)
            session.answerForSnapshot(right: true)
        }
        try await save("session-sweep", SessionView(model: session)) {
            play(.allInstances)
            session.answerForSnapshot(right: true)
            session.answerForSnapshot(right: true)
        }
        try await save("session-typed", SessionView(model: session)) {
            play(.fretNameIt)
            type("gb")
        }
        try await save("session-typed-wrong", SessionView(model: session)) {
            play(.fretNameIt)
            type("f#\r")
        }
        try await save("session-hear", SessionView(model: session)) { play(.hearFindIt) }
        try await save("session-overtime", SessionView(model: session), settle: .milliseconds(1700)) {
            play(.notePlayIt)
            session.passTimeForSnapshot(225 + 12)
            session.skip()
        }
        // + and = in the drill answered by typing.
        try await save("session-extended", SessionView(model: session), settle: .milliseconds(1700)) {
            play(.fretNameIt)
            session.passTimeForSnapshot(225 + 12)
            type("+=")
        }
        try await save("session-ready-after-overtime", SessionView(model: session)) {
            play(.notePlayIt)
            session.end()
            session.done()
            session.start(seed: 1)
            session.next()
            session.passTimeForSnapshot(225 + 72)
            session.next()
        }
        let unheard = SessionViewModel()
        try await save("session-flash", SessionView(model: unheard), sound: silent, settle: .milliseconds(500)) {
            unheard.start(seed: 1)
            unheard.next()
            unheard.passTimeForSnapshot(271)
            unheard.skip()
        }
        // The output failing: with the block that needs sound to come, and in it.
        for (name, kind) in [("coming", DrillKind.notePlayIt), ("mid-block", .hearFindIt)] {
            try await save("session-sound-failed-\(name)", SessionView(model: session)) {
                play(kind)
                session.soundOutput = silent
                session.soundChanged()
            }
        }
        try await save("session-paused", SessionView(model: session)) {
            play(.notePlayIt)
            session.pause()
        }
        try await save("session-paused-notice", SessionView(model: session)) {
            play(.notePlayIt)
            session.pause(notice: "Scarlett 2i2 was disconnected.")
        }
        try await save("session-paused-no-input", SessionPlayingView(model: session)) {
            play(.notePlayIt)
            session.inputChanged(AudioInputState(permission: .granted, device: nil, devices: [], isRunning: false))
            session.pause(notice: "Scarlett 2i2 was disconnected.")
        }
        // By itself, since the window's sidebar isn't drawn.
        try await save("sidebar-session-paused", Sidebar(selection: .constant(.explorer), pausedScreens: [.session, .drill]),
                       size: CGSize(width: 200, height: 240))
        // Esc in the drill answered by typing, then keys in the whole window.
        try await save("session-ending", SessionView(model: session)) {
            play(.fretNameIt)
            type("g\u{1b}")
        }
        try await save("session-paused-by-keys", ContentView(), settle: .milliseconds(1600)) {
            focusSidebar()
            type("\r p")
        }
        try await save("session-resumed-by-keys", ContentView(), settle: .milliseconds(1600)) {
            focusSidebar()
            type("\r \u{1b}\u{1b}p")
        }
        try await save("session-ended-by-keys", ContentView(), settle: .milliseconds(1600)) {
            focusSidebar()
            type("\r s\u{1b}\r")
        }
        try await save("session-summary", SessionView(model: session)) {
            play(.notePlayIt)
            session.end()
            session.done()
            session.start(seed: 1)
            while session.isActive {
                session.next()
                session.skip()
                session.answerForSnapshot(right: false)
                session.answerForSnapshot(right: true)
                session.next()
            }
        }
        try await save("session-summary-nothing-done", SessionView(model: session)) {
            play(.notePlayIt)
            session.end()
        }
    }

    private static var newestWindow: NSWindow? { NSApp.windows.last { $0.isVisible } }

    private static func focusSidebar() {
        func list(in view: NSView) -> NSView? { view is NSTableView ? view : view.subviews.lazy.compactMap(list).first }
        guard let window = newestWindow, let list = window.contentView.flatMap(list), window.makeFirstResponder(list) else {
            preconditionFailure("No sidebar to focus")
        }
    }

    /// Sends key presses to the window being saved.
    private static func type(_ keys: String) {
        guard let window = NSApp.windows.last(where: \.isVisible) else { return }
        for key in keys {
            let code: UInt16 = key == "\r" ? 36 : 0
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                            windowNumber: window.windowNumber, context: nil, characters: String(key),
                                            charactersIgnoringModifiers: String(key), isARepeat: false, keyCode: code) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    /// Hosts `view` in an offscreen window, lets it lay out, applies `prepare`, and writes `<name>.png`.
    private static func save(_ name: String, _ view: some View, size: CGSize = screenSize, log: AttemptLog = .inMemory(),
                             sound: AppSoundOutput = AppSoundOutput(isInert: true),
                             settle: Duration = .milliseconds(400), prepare: () -> Void = {}) async throws {
        let host = NSHostingController(rootView: view.frame(width: size.width, height: size.height).environment(audioInput)
            .environment(sound).environment(log).defaultAppStorage(emptyDefaults))
        host.sceneBridgingOptions = [.title, .toolbars]
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(400))
        prepare()
        try await Task.sleep(for: settle)

        // The window frame gives the title bar and toolbar. Its content can come out blank (the idle drill), so the
        // content's own layer is drawn over it.
        guard let frameView = window.contentView?.superview, let layer = host.view.layer,
              let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
            throw SnapshotError.couldNotRender(name)
        }
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else {
            throw SnapshotError.couldNotRender(name)
        }
        host.view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let content = CGRect(origin: .zero, size: size)
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fill(content)
            context.clip(to: content)
            context.translateBy(x: 0, y: size.height)     // the layer is flipped
            context.scaleBy(x: 1, y: -1)
            layer.render(in: context)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.couldNotRender(name)
        }
        let url = URL(fileURLWithPath: environment["GP_SNAPSHOT"] ?? ".").appendingPathComponent("\(name).png")
        try png.write(to: url)
        print(url.path)
        window.close()
        window.contentViewController = nil
        try await Task.sleep(for: .milliseconds(50))
    }

    private enum SnapshotError: Error {
        case couldNotRender(String)
    }
}
#endif
