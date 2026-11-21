// PROTOTYPE — throwaway. A fake "guitar" for the Phase 1 screen prototype: no audio engine,
// no detector. The floating bar drives it (play the right note, a wrong note, detune the tuner).

import Foundation
import Observation
import TheoryCore

#if DEBUG
@Observable @MainActor
final class ProtoListen {
    let fretboard = Fretboard(tuning: .standard)
    var tuning: Tuning { fretboard.tuning }

    // MARK: Input

    var signal = true
    var level: Double = 0.55

    // MARK: Tuner (continuous MIDI number, e.g. 40.12 = E2 +12 cents)

    var tunerMidi: Double = 40.18

    var tunerNearest: Int { Int(tunerMidi.rounded()) }
    var tunerCents: Double { (tunerMidi - Double(tunerNearest)) * 100 }
    var tunerHz: Double { 440 * pow(2, (tunerMidi - 69) / 12) }
    var tunerNoteName: String { Pitch(tunerNearest).pitchClass.sharpName }
    var tunerOctave: Int { Pitch(tunerNearest).octave }
    var tunerInTune: Bool { abs(tunerCents) <= 5 }

    /// The string (internal index) whose open pitch is nearest the sounding pitch.
    var tunerString: Int {
        tuning.strings.min { abs(Double(tuning.openPitch(ofString: $0).midi) - tunerMidi) < abs(Double(tuning.openPitch(ofString: $1).midi) - tunerMidi) } ?? 0
    }

    /// Cents from the nearest string's open pitch (can exceed ±50 when far off).
    var tunerCentsFromString: Double { (tunerMidi - Double(tuning.openPitch(ofString: tunerString).midi)) * 100 }

    func pluckString(_ string: Int) {
        tunerMidi = Double(tuning.openPitch(ofString: string).midi) + Double.random(in: -0.35...0.35)
        signal = true
    }

    // MARK: Drill

    struct Prompt: Equatable {
        var pitchClass: PitchClass
        var string: Int
    }

    struct Attempt: Identifiable {
        let id = UUID()
        var prompt: Prompt
        var firstRight: Bool
        var time: Double?          // nil = timed out
        var wrongNotes: [String]
        var location: FretboardLocation?
    }

    enum Phase: Equatable {
        case idle, waiting, wrong(String), correct(FretboardLocation), timedOut, paused
    }

    var naturalsOnly = true
    var maxFret = 12
    var strings: Set<Int> = Set(0..<6)
    var inOrder = false

    private(set) var running = false
    private(set) var phase: Phase = .idle
    private(set) var prompt = Prompt(pitchClass: PitchClass(5), string: 2)
    private(set) var promptStart = Date()
    private(set) var attempts: [Attempt] = []
    private var wrongSoFar: [String] = []
    private var orderQueue: [FretboardLocation] = []

    let timeout: Double = 10

    func stringLabel(_ string: Int) -> String {
        "string \(tuning.stringNumber(ofString: string)) (\(tuning.openPitch(ofString: string).pitchClass.sharpName))"
    }

    var promptText: String { "\(prompt.pitchClass.sharpName) on \(stringLabel(prompt.string))" }

    func start() {
        attempts = []
        running = true
        orderQueue = inOrder ? candidateLocations.sorted { ($0.string, $0.fret) < ($1.string, $1.fret) } : []
        next()
    }

    func stop() {
        running = false
        phase = .idle
    }

    func togglePause() {
        guard running else { return }
        phase = phase == .paused ? .waiting : .paused
        if phase == .waiting { promptStart = Date() }
    }

    private var candidateLocations: [FretboardLocation] {
        fretboard.allLocations.filter { loc in
            strings.contains(loc.string) && loc.fret <= maxFret
                && (!naturalsOnly || [0, 2, 4, 5, 7, 9, 11].contains(fretboard.pitch(at: loc).pitchClass.value))
        }
    }

    private func next() {
        wrongSoFar = []
        if inOrder {
            guard !orderQueue.isEmpty else { stop(); return }
            let loc = orderQueue.removeFirst()
            prompt = Prompt(pitchClass: fretboard.pitch(at: loc).pitchClass, string: loc.string)
        } else {
            var p: Prompt
            repeat {
                let loc = candidateLocations.randomElement() ?? FretboardLocation(string: 0, fret: 0)
                p = Prompt(pitchClass: fretboard.pitch(at: loc).pitchClass, string: loc.string)
            } while p == prompt && candidateLocations.count > 2
            prompt = p
        }
        promptStart = Date()
        phase = .waiting
        let token = promptStart
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(self.timeout))
            if self.running, self.promptStart == token, self.phase == .waiting || self.isWrong { self.timeOut() }
        }
    }

    /// Correct locations for the current prompt within the drill's fret range.
    var correctLocations: [FretboardLocation] {
        fretboard.locations(of: prompt.pitchClass).filter { $0.string == prompt.string && $0.fret <= maxFret }
    }

    var elapsed: Double { Date().timeIntervalSince(promptStart) }

    func playCorrect() {
        guard running, phase == .waiting || isWrong else { return }
        let loc = correctLocations.randomElement() ?? FretboardLocation(string: prompt.string, fret: 0)
        attempts.append(Attempt(prompt: prompt, firstRight: wrongSoFar.isEmpty, time: elapsed, wrongNotes: wrongSoFar, location: loc))
        phase = .correct(loc)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if self.running, case .correct = self.phase { self.next() }
        }
    }

    func playWrong() {
        guard running, phase == .waiting || isWrong else { return }
        var pc: PitchClass
        repeat { pc = PitchClass(Int.random(in: 0..<12)) } while pc == prompt.pitchClass
        wrongSoFar.append(pc.sharpName)
        phase = .wrong(pc.sharpName)
    }

    func timeOut() {
        guard running, phase == .waiting || isWrong else { return }
        attempts.append(Attempt(prompt: prompt, firstRight: false, time: nil, wrongNotes: wrongSoFar, location: nil))
        phase = .timedOut
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1800))
            if self.running, self.phase == .timedOut { self.next() }
        }
    }

    var isWrong: Bool { if case .wrong = phase { true } else { false } }

    // MARK: Stats

    var accuracy: Double? {
        attempts.isEmpty ? nil : Double(attempts.filter(\.firstRight).count) / Double(attempts.count)
    }

    var medianTime: Double? {
        let t = attempts.compactMap(\.time).sorted()
        return t.isEmpty ? nil : t[t.count / 2]
    }

    var slowest: [Attempt] {
        Array(attempts.sorted { ($0.time ?? 99) > ($1.time ?? 99) }.prefix(3))
    }

    var stateLine: String {
        "phase \(phase) · \(attempts.count) attempts · acc \(accuracy.map { "\(Int($0 * 100))%" } ?? "–") · median \(medianTime.map { String(format: "%.2fs", $0) } ?? "–")"
    }

    // MARK: Fretboard diagram

    var stringNames: [String] { tuning.openPitches.map { $0.pitchClass.sharpName } }

    var drillDiagram: FretboardDiagram {
        var markers: [FretboardDiagram.Marker] = []
        switch phase {
        case .correct(let loc):
            markers = [.init(location: loc, label: prompt.pitchClass.sharpName, role: .root)]
        case .timedOut:
            markers = correctLocations.map { .init(location: $0, label: prompt.pitchClass.sharpName, role: .tone) }
        default: break
        }
        return FretboardDiagram(stringNames: stringNames, markers: markers, labelMode: .shown)
    }
}
#endif
