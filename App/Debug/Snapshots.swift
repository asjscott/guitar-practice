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
        try await save("explorer", ExplorerView(model: ExplorerViewModel()))

        let tuner = TunerViewModel()
        try await save("tuner-silent", TunerView(model: tuner))
        try await save("tuner-sounding", TunerView(model: tuner)) {
            tuner.show(TunerReading(frequency: 83.3))
        }

        let drill = DrillViewModel()
        try await save("drill-idle", DrillView(model: drill))
        try await save("drill-waiting", DrillView(model: drill)) { drill.start(seed: 1) }
        try await save("drill-wrong", DrillView(model: drill)) {
            drill.start(seed: 1)
            drill.playForSnapshot(right: false)
        }
        // Right answers advance after a short pause, so pause the run to hold the lit neck still.
        try await save("drill-correct", DrillView(model: drill), settle: .milliseconds(150)) {
            drill.start(seed: 1)
            drill.playForSnapshot(right: true)
        }

        try await save("drill-skipped", DrillView(model: drill)) {
            drill.start(seed: 1)
            drill.skip()
        }
        try await save("drill-paused", DrillView(model: drill)) {
            drill.start(seed: 1)
            drill.togglePause()
        }
        try await save("drill-nothing-to-prompt", DrillView(model: drill)) {
            drill.tuning = TuningPreset.eFlatStandard.tuning
            drill.capo = 12
        }

        let sweep = DrillViewModel()
        sweep.kind = .allInstances
        try await save("drill-sweep", DrillView(model: sweep)) {
            sweep.start(seed: 1)
            sweep.playForSnapshot(right: true)
            sweep.playForSnapshot(right: true)
            sweep.skip()
            sweep.playForSnapshot(right: true)
        }
        try await save("drill-sweep-wrong", DrillView(model: sweep)) {
            sweep.stop()
            sweep.start(seed: 1)
            sweep.playForSnapshot(right: true)
            sweep.playForSnapshot(right: false)
        }
        try await save("drill-sweep-paused", DrillView(model: sweep)) {
            sweep.start(seed: 1)
            sweep.togglePause()
        }

        // Typed with real key events, so the key handling is exercised too.
        let naming = DrillViewModel()
        naming.kind = .fretNameIt
        try await save("fret-name-it-waiting", DrillView(model: naming)) { naming.start(seed: 1) }
        try await save("fret-name-it-typed", DrillView(model: naming)) {
            naming.start(seed: 1)
            type("gb")
        }
        try await save("fret-name-it-wrong", DrillView(model: naming)) {
            naming.start(seed: 1)
            type("gb\r")
        }
        try await save("fret-name-it-right", DrillView(model: naming), settle: .milliseconds(150)) {
            naming.start(seed: 1)
            naming.answerForSnapshot()
        }
        try await save("fret-name-it-timed-out", DrillView(model: naming), settle: .milliseconds(10_800)) {
            naming.start(seed: 1)
        }

        try await save("drill-not-saving", DrillView(), log: .inMemory(problem: "The file couldn’t be opened."))

        try await saveSession()

        try await save("settings-instrument", InstrumentSettingsView(), size: CGSize(width: 520, height: 640))
        try await save("settings-audio", AudioSettingsView(), size: CGSize(width: 520, height: 480))
    }

    private static func saveSession() async throws {
        let problems: [(String, SessionProblem)] = [
            ("access", .noAccess), ("input", .noInput),
            ("prompts", .nothingToPrompt("No natural notes in these frets and strings. Choose All notes.")),
        ]
        for (name, problem) in problems {
            try await save("session-setup-no-\(name)", SessionSetupView(
                minutes: .constant(10), naturalsOnly: .constant(false), range: .constant(.wholeNeck),
                blocks: SessionViewModel().plan(), problem: problem, start: {}))
        }
        let session = SessionViewModel()
        try await save("session-setup", SessionView(model: session))

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
            session.leave()
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
        try await save("session-summary", SessionView(model: session)) {
            play(.notePlayIt)
            session.leave()
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
            session.leave()
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
                             settle: Duration = .milliseconds(400), prepare: () -> Void = {}) async throws {
        let host = NSHostingController(rootView: view.frame(width: size.width, height: size.height).environment(audioInput).environment(log)
            .defaultAppStorage(emptyDefaults))
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
