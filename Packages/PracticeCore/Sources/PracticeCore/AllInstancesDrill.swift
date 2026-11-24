import TheoryCore

extension DrillKind {
    public static let allInstances = DrillKind(
        id: "allInstances", module: .notes, title: "All instances",
        instructions: "Find every one, string 6 to string 1, lowest fret first.",
        symbol: "square.grid.3x3", repeatTitle: "Restart", rules: AllInstancesRules.self)
}

/// All instances: sweeps. The engine sees one prompt, and records one attempt, per fretboard location; the prompts
/// of a sweep share its number. R starts the same note again, as a new sweep.
public struct AllInstancesRules: DrillRules {
    public static var kind: DrillKind { .allInstances }

    public let setup: DrillSetup
    private var chooser: PromptChooser
    /// The current sweep's note and number, and its locations still to prompt.
    private var note: PitchClass?
    private var sweep = -1
    private var queue: [FretboardLocation] = []
    private var unswept: [PitchClass] = []

    public init(setup: DrillSetup) {
        self.setup = setup
        chooser = PromptChooser(setup: setup)
    }

    public mutating func nextPrompt(after previous: NotePrompt?) -> NotePrompt? {
        if queue.isEmpty {
            if unswept.isEmpty { unswept = notesInRange }
            guard let next = chooser.choose(from: unswept, avoiding: note, note: { $0 }) else { return nil }
            unswept.removeAll { $0 == next }
            startSweep(of: next)
        }
        let location = queue.removeFirst()
        return setup.prompt(at: location, sweep: sweep)
    }

    private mutating func startSweep(of note: PitchClass) {
        self.note = note
        sweep += 1
        queue = setup.sweepLocations(of: note)
    }

    /// Each note that can be swept, once.
    private var notesInRange: [PitchClass] {
        var seen = Set<PitchClass>()
        return setup.candidateLocations.map { setup.fretboard.pitch(at: $0).pitchClass }.filter { seen.insert($0).inserted }
    }

    public func judge(_ answer: DrillAnswer, for prompt: NotePrompt) -> DrillJudgement {
        setup.judgeExactPitch(answer, for: prompt)
    }

    public func correctLocations(for prompt: NotePrompt) -> [FretboardLocation] {
        prompt.target.map { [$0] } ?? []
    }

    public mutating func repeated() -> DrillRepeat {
        guard let note else { return .ignored }
        startSweep(of: note)
        return .newPrompt
    }

    /// Straight on within a sweep; its end is held long enough to read the total time.
    public func transition(after attempt: Attempt) -> DrillTransition {
        let isLast = attempt.prompt.target == setup.sweepLocations(of: attempt.prompt.pitchClass).last
        return isLast ? DrillTransition(pause: DrillTiming.revealPause, timesFromLastPrompt: false) : .continuous
    }

    public var resumeRule: DrillResumeRule { .samePrompt(keepingWrongAnswers: true) }

    public func display(of moment: DrillMoment) -> DrillDisplay {
        let prompt = moment.prompt
        let locations = setup.sweepLocations(of: prompt.pitchClass)
        // Within a sweep, the nth attempt is at the nth location.
        let dealtWith = moment.attempts.filter { $0.prompt.sweep == prompt.sweep }
        let isOver = dealtWith.count == locations.count

        var display = DrillDisplay(standard: moment, in: setup)
        display.headline = "Every \(prompt.noteName)"
        display.subline = isOver ? "\(locations.count) of \(locations.count)"
            : "next: \(prompt.stringLabel(in: setup.fretboard.tuning)) · \(dealtWith.count + 1) of \(locations.count)"
        display.highlightedStrings = isOver ? [] : [prompt.string]
        display.markers = zip(locations, dealtWith).filter { !$1.skipped }.map {
            DrillDisplay.Marker(location: $0, label: prompt.noteName, isAnswer: !$1.timedOut)
        }
        display.chips = locations.enumerated().map { index, location in
            chip(for: location, attempt: index < dealtWith.count ? dealtWith[index] : nil, isCurrent: index == dealtWith.count)
        }
        if display.result != .wrong, let last = dealtWith.last {
            display.feedback = feedback(after: last) ?? display.feedback
            if isOver, let total = SweepResult(attempts: dealtWith, in: setup)?.summaryLine {
                display.feedback = last.timedOut ? "\(display.feedback) · \(total)" : total
            }
        }
        return display
    }

    private func feedback(after attempt: Attempt) -> String? {
        if attempt.timedOut, let target = attempt.prompt.target { return "Time's up — it was fret \(target.fret)" }
        return attempt.rightAnswerText
    }

    private func chip(for location: FretboardLocation, attempt: Attempt?, isCurrent: Bool) -> DrillDisplay.Chip {
        let state: DrillDisplay.Chip.State = switch attempt?.outcome {
        case .answered: .found
        case .timedOut: .timedOut
        case .skipped: .skipped
        case nil: isCurrent ? .current : .waiting
        }
        let text = switch state {
        case .found, .timedOut: "fret \(location.fret)"
        case .skipped: "skip"
        case .current, .waiting: "–"
        }
        let tuning = setup.fretboard.tuning
        return DrillDisplay.Chip(title: "\(tuning.stringNumber(ofString: location.string))",
                                 spokenTitle: tuning.stringLabel(ofString: location.string), text: text, state: state)
    }
}

extension DrillSetup {
    /// A sweep's locations, in the order they are found: string 6 first, then by fret.
    func sweepLocations(of note: PitchClass) -> [FretboardLocation] {
        locationsInRange.filter { fretboard.pitch(at: $0).pitchClass == note }
    }
}

/// One sweep in a run, finished or not.
public struct SweepResult: Hashable, Sendable {
    public let noteName: String
    public let locationCount: Int
    /// Locations found or revealed.
    public let doneCount: Int
    /// Nil unless the sweep is complete: every location answered or timed out, none skipped. A timeout counts as its
    /// time limit; time paused isn't counted.
    public let totalTime: Duration?

    /// From one sweep's attempts; nil when there are none.
    init?(attempts: [Attempt], in setup: DrillSetup) {
        guard let prompt = attempts.first?.prompt else { return nil }
        noteName = prompt.noteName
        locationCount = setup.sweepLocations(of: prompt.pitchClass).count
        doneCount = attempts.filter { !$0.skipped }.count
        totalTime = doneCount == locationCount
            ? attempts.reduce(.zero) { $0 + ($1.responseTime ?? AllInstancesRules.timeout) } : nil
    }

    /// "Every C — 14.20 s", or "Every C — 3 of 6" when incomplete.
    public var summaryLine: String {
        "Every \(noteName) — " + (totalTime.map { "\(secondsText($0, decimals: 2)) s" } ?? "\(doneCount) of \(locationCount)")
    }
}

extension Drill {
    /// The run's sweeps that have an attempt, oldest first; none in drills other than All instances.
    public var sweeps: [SweepResult] {
        Dictionary(grouping: attempts.filter { $0.prompt.sweep != nil }) { $0.prompt.sweep ?? 0 }
            .sorted { $0.key < $1.key }
            .compactMap { SweepResult(attempts: $0.value, in: setup) }
    }
}
