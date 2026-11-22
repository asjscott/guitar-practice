import ListenCore

/// One listener output, time stamped at the end of the block it came from.
struct TimedOutput {
    let time: Double
    let output: ListenerOutput
}

/// Feeds samples to a listener in tap-sized blocks and collects every output.
func feed(
    _ samples: [Float],
    to listener: inout Listener,
    sampleRate: Double = Signals.sampleRate,
    blockSize: Int = 512,
    startTime: Double = 0
) -> [TimedOutput] {
    var results: [TimedOutput] = []
    var start = 0
    while start < samples.count {
        let end = min(start + blockSize, samples.count)
        let time = startTime + Double(start) / sampleRate
        let output = listener.process(samples[start..<end], sampleRate: sampleRate, time: time)
        results.append(TimedOutput(time: startTime + Double(end) / sampleRate, output: output))
        start = end
    }
    return results
}

/// Feeds samples to a fresh listener and returns the tuner readings
/// between two times (seconds from the start); nil means no signal.
func tunerReadings(
    _ samples: [Float],
    from: Double,
    to: Double,
    sampleRate: Double = Signals.sampleRate,
    blockSize: Int = 512
) -> [TunerReading?] {
    var listener = Listener()
    return feed(samples, to: &listener, sampleRate: sampleRate, blockSize: blockSize)
        .filter { $0.time >= from && $0.time <= to }
        .map(\.output.tunerReading)
}

/// One played note, with the stream time of the block end where it was reported.
struct ReportedNote {
    let reportedAt: Double
    let note: PlayedNote
}

/// Feeds samples to a fresh listener and returns every played note it reports.
func reportedNotes(
    _ samples: [Float],
    sampleRate: Double = Signals.sampleRate,
    blockSize: Int = 512,
    startTime: Double = 0
) -> [ReportedNote] {
    var listener = Listener()
    return feed(samples, to: &listener, sampleRate: sampleRate, blockSize: blockSize, startTime: startTime)
        .flatMap { timed in timed.output.playedNotes.map { ReportedNote(reportedAt: timed.time, note: $0) } }
}

/// Feeds samples to a fresh listener and returns every played note it reports.
func playedNotes(
    _ samples: [Float],
    sampleRate: Double = Signals.sampleRate,
    blockSize: Int = 512,
    startTime: Double = 0
) -> [PlayedNote] {
    reportedNotes(samples, sampleRate: sampleRate, blockSize: blockSize, startTime: startTime).map(\.note)
}
