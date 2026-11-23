#if DEBUG
import AppKit
import ListenCore
import SwiftUI
import TheoryCore

/// Renders the app's screens to PNGs and quits, when `GP_SNAPSHOT=<dir>` is set (see `scripts/snapshot`).
///
/// Draws the app's own offscreen windows, native controls included, so it needs no screen-recording permission.
/// Audio input is inert, so it never asks for the microphone either. Add a `save` for each new screen or state.
/// Not faithful: window titles ("Untitled"), and toolbar buttons in dark mode (white blobs).
@MainActor
enum Snapshots {
    private static let environment = ProcessInfo.processInfo.environment
    private static let screenSize = CGSize(width: 1100, height: 620)
    private static let audioInput = AudioInputService(defaults: emptyDefaults, isInert: true)
    /// No saved input device, so the audio line shows the system default rather than a fallback warning.
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
        // PROTOTYPE
        try await save("proto-root", PrototypeSessionRoot(), size: CGSize(width: 920, height: 600))
        for key in ["S1", "S2", "S3", "S4"] {
            for stage in [ProtoStage.setup, .ready, .paused, .summary] {
                let s = ProtoSession()
                s.stage = stage
                if stage == .ready { s.elapsedInBlock = 0 }
                s.index = stage == .ready ? 0 : 1
                try await save("proto-\(key)-\(stage.rawValue)", PrototypeSessionVariant(key: key, s: s))
            }
            for (i, drill) in ProtoDrill.allCases.enumerated() {
                let s = ProtoSession()
                s.stage = .playing
                s.index = i
                s.result = ProtoResult.allCases[i]
                if drill == .all { s.elapsedInBlock = 470 }
                try await save("proto-\(key)-drill\(i)", PrototypeSessionVariant(key: key, s: s))
            }
        }

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

        try await save("settings-instrument", InstrumentSettingsView(), size: CGSize(width: 520, height: 640))
        try await save("settings-audio", AudioSettingsView(), size: CGSize(width: 520, height: 480))
    }

    /// Hosts `view` in an offscreen window, lets it lay out, applies `prepare`, and writes `<name>.png`.
    private static func save(_ name: String, _ view: some View, size: CGSize = screenSize,
                             settle: Duration = .milliseconds(400), prepare: () -> Void = {}) async throws {
        let host = NSHostingController(rootView: view.frame(width: size.width, height: size.height).environment(audioInput))
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
