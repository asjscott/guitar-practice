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

    /// Only screens whose names start with one of these are rendered; none means every screen.
    private static let onlyPrefixes = (environment["GP_SNAPSHOT_ONLY"] ?? "").split(separator: ",").map(String.init)
    private static let wantsSheet = environment["GP_SNAPSHOT_SHEET"] == "1"
    private static var sheet = ContactSheet()
    private static var savedCount = 0

    static var isRequested: Bool { environment["GP_SNAPSHOT"] != nil }

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: environment["GP_SNAPSHOT_APPEARANCE"] == "dark" ? .darkAqua : .aqua)
        Task {
            emptyDefaults.removePersistentDomain(forName: "GuitarPractice.snapshots")
            do {
                try await saveAll()
                guard savedCount > 0 else { throw SnapshotError.noScreenMatches(onlyPrefixes) }
                try saveSheet()
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
        try await save("drill-paused-no-input", DrillView(model: drill), neededBy: "drill-back-while-paused") {
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

        let triads = DrillViewModel()
        triads.kind = .triadPlayIt
        try await save("triad-idle", DrillView(model: triads))
        triads.stop()
        try await save("triad-waiting", DrillView(model: triads)) { triads.start(seed: 1) }
        triads.stop()
        try await save("triad-one-note", DrillView(model: triads)) {
            triads.start(seed: 1)
            triads.playForSnapshot(right: true)
        }
        triads.stop()
        for stage in [FadeStage.faded, .hidden] {
            try await save("triad-\(stage.rawValue)", DrillView(model: triads)) {
                triads.options.triadFade = stage
                triads.start(seed: 1)
                triads.playForSnapshot(right: true)
            }
            triads.stop()
        }
        try await save("triad-hint", DrillView(model: triads)) {
            triads.start(seed: 1)
            triads.hint(isShown: true)
        }
        triads.stop()
        try await save("triad-wrong", DrillView(model: triads)) {
            triads.start(seed: 1)
            triads.playForSnapshot(right: true)
            triads.playForSnapshot(right: false)
        }
        triads.stop()
        try await save("triad-right", DrillView(model: triads), settle: .milliseconds(150)) {
            triads.start(seed: 1)
            for _ in 0..<3 { triads.playForSnapshot(right: true) }
        }
        triads.stop()
        try await save("triad-revealed", DrillView(model: triads)) {
            triads.start(seed: 1)
            triads.playForSnapshot(right: true)
            triads.timeOutForSnapshot()
        }
        triads.stop()
        try await save("triad-paused", DrillView(model: triads)) {
            triads.start(seed: 1)
            triads.togglePause()
        }
        triads.stop()
        // Short, with the longest headline, a key with flats and the whole neck.
        try await save("triad-whole-neck", DrillView(model: triads), size: CGSize(width: 920, height: 520)) {
            triads.options.key = .minor(.bFlat)
            triads.options.frets = 0...22
            triads.options.stringSets = [.eAD, .aDG]
            triads.start(seed: 2)
            triads.playForSnapshot(right: true)
        }
        triads.stop()
        try await save("triad-no-voicing", DrillView(model: triads)) {
            triads.options = DrillOptions()
            triads.options.stringSets = [.eAD]
            triads.options.inversions = [.root]
            triads.capo = 12
        }

        try await saveProgressions()

        let climb = DrillViewModel()
        climb.kind = .inversions
        climb.options.stringSets = [.dGB]
        func playVoicing() { for _ in 0..<3 { climb.playForSnapshot(right: true) } }
        try await save("inversions-idle", DrillView(model: climb))
        climb.stop()
        try await save("inversions-shown", DrillView(model: climb)) { climb.start(seed: 1) }
        climb.stop()
        climb.options.triadFade = .hidden
        try await save("inversions-waiting", DrillView(model: climb)) { climb.start(seed: 1) }
        climb.stop()
        try await save("inversions-climbing", DrillView(model: climb)) {
            climb.start(seed: 1)
            playVoicing()
            climb.skip()
            climb.skip()
            climb.playForSnapshot(right: true)
        }
        climb.stop()
        try await save("inversions-wrong", DrillView(model: climb)) {
            climb.start(seed: 1)
            climb.playForSnapshot(right: true)
            climb.playForSnapshot(right: false)
        }
        climb.stop()
        try await save("inversions-right", DrillView(model: climb), settle: .milliseconds(150)) {
            climb.start(seed: 1)
            playVoicing()
        }
        climb.stop()
        try await save("inversions-revealed", DrillView(model: climb)) {
            climb.start(seed: 1)
            climb.playForSnapshot(right: true)
            climb.timeOutForSnapshot()
        }
        climb.stop()
        try await save("inversions-paused", DrillView(model: climb)) {
            climb.start(seed: 1)
            climb.togglePause()
        }
        climb.stop()
        // Short, with the longest line: the whole neck.
        try await save("inversions-whole-neck", DrillView(model: climb), size: CGSize(width: 920, height: 520)) {
            climb.options = DrillOptions()
            climb.options.key = .minor(.bFlat)
            climb.options.frets = 0...22
            climb.start(seed: 1)
            climb.playForSnapshot(right: true)
        }
        climb.stop()
        try await save("inversions-none", DrillView(model: climb)) {
            climb.options = DrillOptions()
            climb.options.stringSets = [.dGB]
            climb.capo = 12
        }

        try await savePasses()

        try await save("drill-not-saving", DrillView(model: DrillViewModel()), log: .inMemory(problem: "The file couldn’t be opened."))

        // A menu can't be drawn offscreen, so its items are laid out inline.
        try await save("drill-picker", DrillPicker(kind: .constant(.notePlayIt), kinds: DrillKind.all)
            .pickerStyle(.inline).padding(), size: CGSize(width: 320, height: 360))

        try await saveNecks()
        try await saveSession()

        try await save("settings-instrument", InstrumentSettingsView(), size: CGSize(width: 520, height: 640))
        let activeSessions = ActiveSessions()
        activeSessions.set(UUID(), isActive: true)
        try await save("settings-instrument-locked", InstrumentSettingsView().environment(activeSessions),
                       size: CGSize(width: 520, height: 700))
        try await save("settings-audio", AudioSettingsView(), size: CGSize(width: 520, height: 480))
        try await saveMetronome()
    }

    private static func savePasses() async throws {
        let noOutput = AppSoundOutput(isInert: true, problem: "There’s no sound output device.")
        let scales = DrillViewModel()
        scales.kind = .upAndDown
        scales.options.key = .major(.a)
        scales.options.position = Position.ID(system: .caged, number: CAGEDShape.d.number)
        func run(_ rightNotes: Int = 0, then: () -> Void = {}) {
            scales.stop()
            // As it was before any pass moved it.
            emptyDefaults.removeObject(forKey: MetronomeSettings.Key.tempo(of: .upAndDown))
            scales.start(seed: 1)
            for _ in 0..<rightNotes { scales.playForSnapshot(right: true) }
            then()
        }
        try await save("pass-idle", DrillView(model: scales))
        try await save("pass-count-in", DrillView(model: scales), settle: .milliseconds(1600)) { run() }
        try await save("pass-playing", DrillView(model: scales)) { run(11) }
        try await save("pass-wrong", DrillView(model: scales)) {
            run(11) { scales.playForSnapshot(right: false) }
        }
        try await save("pass-revealed", DrillView(model: scales)) {
            run(11) { scales.timeOutForSnapshot() }
        }
        try await save("pass-clean", DrillView(model: scales), settle: .milliseconds(150)) { run(33) }
        for stage in FadeStage.allCases {
            scales.stop()
            scales.options.pass.fadeStage = stage
            try await save("pass-fade-\(stage.rawValue)", DrillView(model: scales)) { run(11) }
        }
        try await save("pass-hint", DrillView(model: scales)) {
            run(11) { scales.hint(isShown: true) }
        }
        try await save("pass-hinted", DrillView(model: scales), settle: .milliseconds(150)) {
            run {
                scales.hint(isShown: true)
                scales.hint(isShown: false)
                for _ in 0..<33 { scales.playForSnapshot(right: true) }
            }
        }
        scales.stop()
        scales.options.pass.fadeStage = nil
        try await save("pass-paused", DrillView(model: scales)) {
            run(3) { scales.togglePause() }
        }
        try await save("pass-output-lost", DrillView(model: scales)) {
            run()
            scales.soundOutput = noOutput
            scales.soundProblemChanged()
        }
        try await save("pass-no-output", DrillView(model: scales), sound: noOutput, settle: .milliseconds(1600)) { run() }
        // The panel: on M mid-pass, which pauses; [ and ] then do nothing. Closing it goes on.
        try await save("pass-metronome-panel", DrillView(model: scales), settle: .milliseconds(900)) {
            run(3)
            type("]mrs[")
        } check: {
            precondition(scales.isPanelOpen && scales.isPaused && scales.passSettings.tempo == 64)
        }
        try await save("pass-metronome-panel-closed", DrillView(model: scales), settle: .milliseconds(900)) {
            run(3)
            type("mm]]")
        } check: {
            precondition(scales.isRunning && !scales.isPaused && scales.passSettings.tempo == 68)
        }
        try await save("pass-metronome-panel-esc", DrillView(model: scales), settle: .milliseconds(900)) {
            run(3)
            type("m\u{1b}")
        } check: {
            precondition(scales.isRunning && !scales.isPaused && !scales.isPanelOpen)
        }
        try await save("pass-metronome-panel-no-resume", DrillView(model: scales), settle: .milliseconds(900)) {
            run(3)
            scales.isPanelOpen = true
            scales.pause(notice: "The Mac went to sleep.")
            scales.isPanelOpen = false
        } check: {
            precondition(scales.isPaused)
        }
        try await saveFromADegree()
        // Short, with the longest headline, the longest bar and a capo.
        emptyDefaults.set("12/8", forKey: MetronomeSettings.Key.signature)
        defer { emptyDefaults.removeObject(forKey: MetronomeSettings.Key.signature) }
        scales.stop()
        try await save("pass-short", DrillView(model: scales), size: CGSize(width: 1100, height: 440)) {
            scales.capo = 2
            scales.options.key = .minor(.bFlat)
            scales.options.scaleKind = .minorPentatonic
            run(1) { scales.playForSnapshot(right: false) }
        }
        scales.stop()
        try await save("pass-metronome-panel-short", DrillView(model: scales), size: CGSize(width: 1100, height: 400)) {
            run()
            scales.isPanelOpen = true
        }
        scales.stop()
        try await save("pass-none", DrillView(model: scales)) {
            scales.capo = 12
            scales.options.position = Position.ID(system: .caged, number: CAGEDShape.d.number)
        }
        scales.stop()
        try await save("pass-summary", DrillView(model: scales), settle: .milliseconds(1500)) {
            scales.capo = 0
            scales.options.scaleKind = .major
            scales.options.key = .major(.a)
            run(33)
            scales.skip()
            scales.playForSnapshot(right: true)
            // The view has to see it running.
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                scales.stop()
            }
        }
    }

    private static func saveFromADegree() async throws {
        let model = DrillViewModel()
        model.kind = .fromADegree
        model.options.key = .minor(.a)
        model.options.scaleKind = .blues
        model.options.position = Position.ID(system: .caged, number: CAGEDShape.g.number)
        try await save("pass-from-a-degree-idle", DrillView(model: model))
        try await save("pass-from-a-degree", DrillView(model: model)) {
            model.start(seed: 1)
            for _ in 0..<4 { model.playForSnapshot(right: true) }
        }
        model.stop()
    }

    /// Nearest voicing: I–V–vi–IV in G, E shape, at 70 BPM, played along the drawn path.
    private static func saveProgressions() async throws {
        func model() -> DrillViewModel {
            let model = DrillViewModel()
            model.kind = .nearestVoicing
            model.progressionKey = .major(.g)
            model.progression = Progression.named("I–V–vi–IV")!
            model.options.position = Position.ID(system: .caged, number: CAGEDShape.e.number)
            return model
        }
        let idle = model()
        try await save("progression-idle", DrillView(model: idle))
        let noSounds = model()
        try await save("progression-no-sounds", DrillView(model: noSounds),
                       sound: AppSoundOutput(isInert: true, hasBackingSounds: false)) {
            noSounds.setInputBuiltInForSnapshot()
        }
        let countIn = model()
        try await save("progression-count-in", DrillView(model: countIn)) {
            countIn.start(seed: 1)
            countIn.playProgressionForSnapshot(chords: 0, untilBeat: 1.5)
        }
        countIn.stop()
        let shown = model()
        try await save("progression-shown", DrillView(model: shown)) {
            shown.start(seed: 1)
            shown.playProgressionForSnapshot(chords: 1, partial: 2, untilBeat: 9.6)
        }
        shown.stop()
        let faded = model()
        try await save("progression-faded", DrillView(model: faded)) {
            faded.start(seed: 1)
            faded.playProgressionForSnapshot(chords: 8, partial: 2, untilBeat: 37.6)
        }
        faded.stop()
        let hidden = model()
        try await save("progression-hidden-wrong", DrillView(model: hidden)) {
            hidden.start(seed: 1)
            hidden.playProgressionForSnapshot(chords: 18, wrong: [16], partial: 1, untilBeat: 76.8)
        }
        hidden.stop()
        let paused = model()
        try await save("progression-paused", DrillView(model: paused)) {
            paused.start(seed: 1)
            paused.playProgressionForSnapshot(chords: 1, partial: 2, untilBeat: 9.6)
            paused.togglePause()
        }
        paused.stop()
    }

    private static func saveMetronome() async throws {
        let size = CGSize(width: 520, height: 800)
        func choose(_ signature: String, _ emphasis: String) {
            emptyDefaults.set(signature, forKey: MetronomeSettings.Key.signature)
            emptyDefaults.set(emphasis, forKey: MetronomeSettings.Key.emphasis)
        }
        defer {
            for key in MetronomeSettings.Key.all { emptyDefaults.removeObject(forKey: key) }
        }
        choose("4/4", "4/4:1,3")
        try await save("settings-metronome", MetronomeSettingsView(), size: size)
        choose("12/8", "")
        try await save("settings-metronome-12-8", MetronomeSettingsView(), size: size)
        choose("1/8", "1/8:")
        try await save("settings-metronome-1-8", MetronomeSettingsView(), size: size)
        choose("4/4", "4/4:1,3")
        try await save("settings-metronome-no-sound", MetronomeSettingsView(), size: size,
                       sound: AppSoundOutput(isInert: true, problem: "There’s no sound output device."))

        // Listening, on beat 1 and on beat 2, which isn't emphasised.
        let output = AppSoundOutput(isInert: true)
        for (beat, settle) in [(1, 500), (2, 1500)] {
            let metronome = Metronome(output: output, defaults: emptyDefaults)
            try await save("settings-metronome-beat-\(beat)",
                           MetronomeSettingsView().environment(metronome).environment(output),
                           size: size, settle: .milliseconds(settle)) { metronome.listen() }
        }

        // Backing: without its sounds, and listening with the click on beat 2 of the count-in.
        try await save("settings-metronome-no-backing-sounds", MetronomeSettingsView(), size: size,
                       sound: AppSoundOutput(isInert: true, hasBackingSounds: false))
        let metronome = Metronome(output: output, defaults: emptyDefaults)
        let backing = BackingPlayer(output: output, metronome: metronome)
        try await save("settings-metronome-backing", MetronomeSettingsView().environment(metronome).environment(backing)
            .environment(output), size: size, settle: .milliseconds(1100)) { backing.listen(withClick: true) }
        backing.stop()
        try await save("beats-row", BeatsRow(meter: Meter(.fourFour, emphasis: [1, 3]), current: 4).padding(),
                       size: CGSize(width: 260, height: 80))
    }

    /// The neck by itself: zoomed, and at each fade stage.
    private static func saveNecks() async throws {
        let names = Fretboard(tuning: .standard).stringNames(in: nil).map(\.description)
        func save(_ name: String, _ diagram: FretboardDiagram) async throws {
            try await Self.save("neck-\(name)", FretboardView(diagram: diagram).padding(24), size: CGSize(width: 1100, height: 400))
        }
        func zoomed(_ tonic: NoteName, _ shape: CAGEDShape, octave: Int = 0, capo: Int = 0) -> FretboardDiagram {
            let fretboard = Fretboard(tuning: .standard, capo: capo), key = Key.major(tonic)
            let id = Position.ID(system: .caged, number: shape.number, octave: octave)
            guard let position = Theme(key: key, position: id).position(on: fretboard) else {
                preconditionFailure("No such position")
            }
            var diagram = FretboardDiagram(position, in: key, on: fretboard)
            diagram.fretWindow = position.fretWindow
            return diagram
        }
        func stage(isFaint: Bool, rootsOnly: Bool = false) -> FretboardDiagram {
            var diagram = zoomed(.a, .d)
            var lastPlayed = diagram.markers.remove(at: 7)
            lastPlayed.isLastPlayed = true
            if rootsOnly { diagram.markers.removeAll { $0.role != .root } }
            for index in diagram.markers.indices { diagram.markers[index].isFaint = isFaint }
            diagram.markers.append(lastPlayed)
            return diagram
        }
        try await save("whole", FretboardDiagram(stringNames: names, highlightedStrings: [3]))
        try await save("nut", zoomed(.c, .c))
        // The nut shows, without the open strings.
        try await save("first-fret", FretboardDiagram(stringNames: names, fretWindow: 1...8))
        try await save("last-fret", zoomed(.c, .e, octave: 1))
        try await save("capo", zoomed(.d, .c, capo: 2))
        try await save("capo-inside", zoomed(.c, .e, capo: 6))
        try await save("shown", stage(isFaint: false))
        try await save("faded", stage(isFaint: true))
        try await save("hidden", stage(isFaint: true, rootsOnly: true))
        try await save("string-set", FretboardDiagram(
            stringNames: names, fretWindow: 0...12,
            markers: [.init(location: FretboardLocation(string: 2, fret: 4), label: "F♯", role: .tone, isLastPlayed: true)],
            highlightedStrings: Set(StringSet.dGB.strings)))
    }

    private static func saveSession() async throws {
        let problems: [(String, SessionProblem)] = [
            ("access", .input(.noAccess)), ("access-asked", .input(.accessNotGiven)), ("input", .input(.noInput)),
            ("prompts", .nothingToPrompt("No natural notes in these frets and strings. Choose All notes.")),
        ]
        for (name, problem) in problems {
            try await save("session-setup-no-\(name)", SessionSetupView(
                minutes: .constant(10), naturalsOnly: .constant(false), range: .constant(.wholeNeck),
                theme: SessionTheme(Theme(key: .minor(.dSharp), position: Position.ID(system: .threeNotesPerString, number: 2), stringSet: .gBE),
                                    on: Fretboard(tuning: .standard)),
                reroll: nil, blocks: SessionViewModel().plan(), problem: problem, start: {}))
        }
        // A neck that the theme has no position on.
        try await save("session-setup-no-position", SessionSetupView(
            minutes: .constant(10), naturalsOnly: .constant(false), range: .constant(.wholeNeck),
            theme: SessionTheme(Theme(key: .major(.c), position: Position.ID(system: .caged, number: CAGEDShape.d.number), stringSet: .eAD),
                                on: Fretboard(tuning: .standard, capo: 12)),
            reroll: {}, blocks: SessionViewModel().plan(), problem: nil, start: {}))
        try await save("session-setup-no-triads", SessionSetupView(
            minutes: .constant(15), naturalsOnly: .constant(true), range: .constant(.first12),
            theme: SessionTheme(Theme(key: .major(.c), position: Position.ID(system: .caged, number: 3), stringSet: .eAD),
                                on: Fretboard(tuning: .standard)),
            reroll: nil, blocks: SessionPlanner.plan(DrillKind.all.filter { $0.module != .triads }, budget: .seconds(900), day: 1),
            problem: nil, noTriadsNotice: "Triads are left out: no voicing of the key’s chords on E-A-D fits these frets.",
            start: {}))
        let session = SessionViewModel()
        try await save("session-setup", SessionView(model: session))
        try await save("session-setup-short", SessionView(model: session), size: CGSize(width: 1100, height: 480))

        for minutes in [10, 60] {
            try await save("session-setup-modules-\(minutes)", SessionSetupView(
                minutes: .constant(minutes), naturalsOnly: .constant(true), range: .constant(.first12),
                theme: SessionTheme(Theme(key: .major(.bFlat), position: Position.ID(system: .caged, number: 3), stringSet: .dGB),
                                    on: Fretboard(tuning: .standard)),
                reroll: {}, blocks: SessionPlanner.plan(DrillKind.all, budget: .seconds(minutes * 60), day: 1),
                problem: nil, start: {}), size: CGSize(width: 920, height: 620))
        }

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

        /// How long the first block is planned to be, in seconds.
        func firstLength(_ model: SessionViewModel) -> Double { (model.plan().first?.length ?? .zero) / .seconds(1) }
        /// A new session, on the Ready card of a drill.
        func ready(_ kind: DrillKind) {
            session.done()
            session.end()
            session.done()
            // As they were before any pass moved them.
            for kind in DrillKind.all { emptyDefaults.removeObject(forKey: MetronomeSettings.Key.tempo(of: kind)) }
            session.start(seed: 1)
            while session.isActive, session.blockKind != kind {
                session.next()
                session.next()
            }
        }
        /// The same, playing its block.
        func play(_ kind: DrillKind) {
            ready(kind)
            // Any sound of an earlier block is over, so that notes count.
            session.passTimeForSnapshot(2)
            session.next()
        }
        /// Plays the rest of a pass, or some of it.
        func playNotes(_ count: Int = .max) {
            for _ in 0..<min(count, 60) where session.snapshot.display?.pass?.notes.contains(where: { $0.state == .current }) == true {
                session.answerForSnapshot(right: true)
            }
        }
        /// Answers a prompt: the rest of a pass, or a whole voicing.
        func playPrompt() {
            for _ in 0..<(session.blockKind?.module == .triads ? 3 : 1) { session.answerForSnapshot(right: true) }
            playNotes()
        }
        // In 60 minutes every drill has a block.
        emptyDefaults.set(60, forKey: "session.minutes")
        session.setup = SessionSetup(minutes: 60)
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
            session.passTimeForSnapshot(firstLength(session) + 12)
            session.skip()
        }
        // + and = in the drill answered by typing.
        try await save("session-extended", SessionView(model: session), settle: .milliseconds(1700)) {
            play(.fretNameIt)
            session.passTimeForSnapshot(firstLength(session) + 12)
            type("+=")
        }
        try await save("session-ready-after-overtime", SessionView(model: session)) {
            play(.notePlayIt)
            session.end()
            session.done()
            session.start(seed: 1)
            session.next()
            session.passTimeForSnapshot(firstLength(session) + 72)
            session.next()
        }
        try await save("session-summary-60", SessionView(model: session), size: CGSize(width: 920, height: 620)) {
            play(.notePlayIt)
            session.end()
            session.done()
            session.start(seed: 1)
            while session.isActive {
                session.passTimeForSnapshot(2)
                session.next()
                playPrompt()
                session.next()
            }
        }

        try await save("session-scale-ready", SessionView(model: session)) { ready(.upAndDown) }
        try await save("session-scale-count-in", SessionView(model: session), settle: .milliseconds(1600)) { play(.upAndDown) }
        try await save("session-scale", SessionView(model: session)) {
            play(.upAndDown)
            playNotes(11)
        }
        try await save("session-scale-wrong", SessionView(model: session)) {
            play(.upAndDown)
            playNotes(11)
            session.answerForSnapshot(right: false)
        }
        try await save("session-scale-hint", SessionView(model: session)) {
            play(.upAndDown)
            playNotes(4)
            session.hint(isShown: true)
        }
        try await save("session-scale-over", SessionView(model: session), settle: .milliseconds(150)) {
            play(.upAndDown)
            playNotes()
        }
        try await save("session-scale-next", SessionView(model: session), size: CGSize(width: 920, height: 520)) {
            play(.fromADegree)
            session.skip()
            playNotes(3)
        }
        try await save("session-scale-paused", SessionView(model: session)) {
            play(.upAndDown)
            session.pause()
        }
        try await save("session-scale-chiming", SessionView(model: session), settle: .milliseconds(150)) {
            play(.upAndDown)
            let length = session.plan().first { $0.kind == .upAndDown }?.length ?? .zero
            session.passTimeForSnapshot(length / .seconds(1) - 29)
            session.skip()
        }
        // M pauses; the session's keys then do nothing, and [ and ] neither. Closing goes on.
        try await save("session-scale-panel", SessionView(model: session), settle: .milliseconds(900)) {
            play(.upAndDown)
            playNotes(3)
            type("]m srp+[")
        } check: {
            precondition(session.isPanelOpen && session.stage == .paused && session.blockKind == .upAndDown)
            precondition(session.passSettings?.tempo == 64)
        }
        try await save("session-scale-panel-esc", SessionView(model: session), settle: .milliseconds(900)) {
            play(.upAndDown)
            playNotes(3)
            type("m\u{1b}")
        } check: {
            precondition(session.stage == .playing && !session.isPanelOpen && !session.asksToEnd)
        }
        try await save("session-scale-panel-ready", SessionView(model: session), size: CGSize(width: 920, height: 520),
                       settle: .milliseconds(900)) {
            ready(.upAndDown)
            type("m")
        } check: {
            precondition(session.isPanelOpen && session.stage == .paused)
        }
        try await save("session-scale-panel-ready-closed", SessionView(model: session), settle: .milliseconds(900)) {
            ready(.upAndDown)
            type("mm")
        } check: {
            precondition(session.stage == .ready)
        }
        try await save("session-scale-output-lost", SessionView(model: session)) {
            play(.upAndDown)
            session.soundOutput = silent
            session.soundChanged()
        }
        try await save("session-scale-no-output", SessionView(model: session), sound: silent, settle: .milliseconds(1600)) {
            play(.upAndDown)
        }

        for (name, kind) in [("triad", DrillKind.triadPlayIt), ("climb", .inversions)] {
            try await save("session-\(name)-waiting", SessionView(model: session)) { play(kind) }
            try await save("session-\(name)-wrong", SessionView(model: session)) {
                play(kind)
                session.answerForSnapshot(right: true)
                session.answerForSnapshot(right: false)
            }
            try await save("session-\(name)-right", SessionView(model: session), size: CGSize(width: 920, height: 520),
                           settle: .milliseconds(150)) {
                play(kind)
                for _ in 0..<3 { session.answerForSnapshot(right: true) }
            }
        }
        try await save("session-triad-ready", SessionView(model: session)) { ready(.triadPlayIt) }

        let unheard = SessionViewModel()
        try await save("session-flash", SessionView(model: unheard), sound: silent, settle: .milliseconds(500)) {
            unheard.start(seed: 1)
            unheard.next()
            unheard.passTimeForSnapshot(firstLength(unheard) - 29)
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
        emptyDefaults.removeObject(forKey: "session.minutes")
        session.setup = SessionSetup()
        try await save("session-summary", SessionView(model: session)) {
            play(.notePlayIt)
            session.end()
            session.done()
            session.start(seed: 1)
            while session.isActive {
                session.passTimeForSnapshot(2)
                session.next()
                session.skip()
                session.answerForSnapshot(right: false)
                playPrompt()
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

    private static func isWanted(_ name: String) -> Bool {
        onlyPrefixes.isEmpty || onlyPrefixes.contains { name.hasPrefix($0) }
    }

    private static func saveSheet() throws {
        guard wantsSheet else { return }
        for (index, page) in sheet.pages().enumerated() { try write(page, as: "sheet-\(index + 1)") }
    }

    private static func write(_ png: Data, as name: String) throws {
        let url = URL(fileURLWithPath: environment["GP_SNAPSHOT"] ?? ".").appendingPathComponent("\(name).png")
        try png.write(to: url)
        print(url.path)
    }

    /// Hosts `view` in an offscreen window, lets it lay out, applies `prepare`, runs `check` and writes `<name>.png`.
    /// Skipped if `--only` leaves it out, so a screen must not rely on an earlier one's `prepare`; if it has to, the
    /// earlier one names it in `neededBy`.
    private static func save(_ name: String, _ view: some View, size: CGSize = screenSize, log: AttemptLog = .inMemory(),
                             sound: AppSoundOutput = AppSoundOutput(isInert: true),
                             settle: Duration = .milliseconds(400), neededBy follower: String? = nil,
                             prepare: () -> Void = {}, check: () -> Void = {}) async throws {
        guard isWanted(name) || follower.map(isWanted) == true else { return }
        let metronome = Metronome(output: sound, defaults: emptyDefaults)
        let host = NSHostingController(rootView: view.frame(width: size.width, height: size.height).environment(audioInput)
            .environment(sound).environment(metronome).environment(BackingPlayer(output: sound, metronome: metronome))
            .environment(log).defaultAppStorage(emptyDefaults))
        host.sceneBridgingOptions = [.title, .toolbars]
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(400))
        prepare()
        try await Task.sleep(for: settle)
        check()

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
        if let sheet = window.attachedSheet?.contentView?.superview,
           let picture = sheet.bitmapImageRepForCachingDisplay(in: sheet.bounds) {
            sheet.cacheDisplay(in: sheet.bounds, to: picture)
            guard let image = picture.cgImage else { throw SnapshotError.couldNotRender(name) }
            context.translateBy(x: 0, y: size.height)     // not flipped
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: (size.width - sheet.bounds.width) / 2,
                                                      y: (size.height - sheet.bounds.height) / 2,
                                                      width: sheet.bounds.width, height: sheet.bounds.height))
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.couldNotRender(name)
        }
        try write(png, as: name)
        if wantsSheet { sheet.add(name, bitmap) }
        savedCount += 1
        window.close()
        window.contentViewController = nil
        try await Task.sleep(for: .milliseconds(50))
    }

    private enum SnapshotError: Error {
        case couldNotRender(String)
        case noScreenMatches([String])
    }
}
#endif
