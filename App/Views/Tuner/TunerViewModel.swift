import ListenCore
import Observation
import os
import TheoryCore

/// The Tuner screen's state. Adapts the ListenCore listener (fed by the audio input service) to what the
/// T1 "Needle" layout shows: the note, the needle's cents, the "+18 cents · 83.3 Hz" line and the string chips.
///
/// The listener runs on the audio tap's thread inside a lock; each block's tuner reading hops to the main
/// actor. With no signal the last reading is kept, marked as not sounding, so the view can grey it out.
@MainActor @Observable
final class TunerViewModel {
    /// How close a sound is to its target, for colouring the needle, note and string chip.
    enum Accuracy: Equatable {
        /// Within ±5 cents.
        case inTune
        /// Within ±20 cents.
        case close
        case off

        init(cents: Double) {
            switch abs(cents) {
            case ...TunerReading.inTuneCents: self = .inTune
            case ...Self.closeCents: self = .close
            default: self = .off
            }
        }

        static let closeCents = 20.0
    }

    /// One string chip: "6" over "E2".
    struct StringChip: Identifiable, Equatable {
        /// String index (0 = string 6).
        let id: Int
        let number: Int
        let openPitchName: String
        /// Set on the string nearest the sounding note, while there is signal.
        let accuracy: Accuracy?
    }

    /// The tuning whose open strings the chips show. The capo is ignored: the tuner tunes open strings.
    var tuning: Tuning = .standard

    /// The latest reading, kept after the sound stops; nil until something has been heard.
    private(set) var reading: TunerReading?
    /// True while the listener hears a pitch; false keeps `reading` on screen, greyed out.
    private(set) var isSounding = false

    @ObservationIgnored private let listener = OSAllocatedUnfairLock(initialState: Listener())

    // MARK: - Display

    /// The note name ("F♯", flats in E♭ standard), or a dash before anything has been heard.
    var noteName: String {
        guard let pitch else { return "–" }
        return tuning.noteName(of: pitch.pitchClass).description
    }

    /// The octave number shown beside the note ("2" for E2); empty before anything has been heard.
    var octave: String {
        pitch.map { "\($0.octave)" } ?? ""
    }

    /// Cents from the nearest pitch, for the needle; 0 before anything has been heard.
    var cents: Double { reading?.cents ?? 0 }

    /// The note's accuracy while sounding; nil when silent (greyed out).
    var accuracy: Accuracy? {
        guard isSounding, let reading else { return nil }
        return Accuracy(cents: reading.cents)
    }

    /// "+18 cents · 83.3 Hz" while sounding, else "Play a string".
    var detail: String {
        guard isSounding, let reading else { return "Play a string" }
        return String(format: "%+.0f cents · %.1f Hz", reading.cents.rounded() == 0 ? 0 : reading.cents, reading.frequency)
    }

    /// The tuning's strings, string 6 first, with the one nearest the sounding note lit.
    var stringChips: [StringChip] {
        let nearest = nearestString
        return tuning.strings.map { string in
            StringChip(id: string,
                       number: tuning.stringNumber(ofString: string),
                       openPitchName: tuning.openPitchNames[string],
                       accuracy: string == nearest?.string ? nearest.map { Accuracy(cents: $0.cents) } : nil)
        }
    }

    /// "Standard tuning · A4 = 440 Hz".
    var windowSubtitle: String {
        "\(tuning.preset?.name ?? "Custom") tuning · A4 = 440 Hz"
    }

    private var pitch: Pitch? { reading.map { Pitch($0.midiNote) } }

    /// The string nearest the sounding note and the cents from its open pitch (may be well beyond ±50).
    private var nearestString: (string: Int, cents: Double)? {
        guard isSounding, let reading, let pitch else { return nil }
        let string = tuning.nearestString(to: pitch, cents: reading.cents)
        let semitones = (pitch - tuning.openPitch(ofString: string)).semitones
        return (string, Double(semitones) * 100 + reading.cents)
    }

    // MARK: - Listening

    /// The consumer for `.listensToAudioInput(_:)`: runs the listener on the tap thread, shows results here.
    var audioConsumer: AudioInputConsumer {
        let listener = self.listener
        return { [weak self] block in
            let output = listener.withLock { listener in
                if block.startsNewStream { listener = Listener() }
                return listener.process(block.samples, sampleRate: block.sampleRate, time: block.streamTime)
            }
            Task { @MainActor [weak self] in self?.show(output.tunerReading) }
        }
    }

    /// Shows a reading; nil (no signal) keeps the last one, greyed out.
    func show(_ newReading: TunerReading?) {
        if let newReading {
            if newReading != reading { reading = newReading }
            if !isSounding { isSounding = true }
        } else if isSounding {
            isSounding = false
        }
    }

    /// Marks the tuner silent (keeping the last note), e.g. when the screen closes.
    func stopSounding() {
        isSounding = false
    }
}
