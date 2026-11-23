import TheoryCore

// Text the drill screen shows for attempts and run stats, worked out here so it can be tested.

extension Attempt {
    /// One summary row: "F on string 3 (G) — 2.31 s · played E, G first", or "… — timed out".
    public func summaryLine(in tuning: Tuning) -> String {
        let time = responseTime.map { "\(secondsText($0, decimals: 2)) s" } ?? "timed out"
        let wrong = wrongNotes.isEmpty ? "" : " · played \(wrongNotes.map(\.sharpName).joined(separator: ", ")) first"
        return "\(prompt.text(in: tuning)) — \(time)\(wrong)"
    }

    /// The response time for the attempt strip, one decimal: "2.3"; "—" for a timeout.
    public var shortTimeText: String {
        responseTime.map { secondsText($0, decimals: 1) } ?? "—"
    }

    /// The feedback after a right answer: "Fret 7 · 0.82 s"; nil for a timeout.
    public var rightAnswerText: String? {
        guard let location, let responseTime else { return nil }
        return "Fret \(location.fret) · \(secondsText(responseTime, decimals: 2)) s"
    }
}

extension RunStats {
    /// First-try accuracy as a whole percentage, "83%"; "–" before any prompt is done.
    public var firstTryText: String {
        firstTryAccuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
    }

    /// The median response time, "1.24 s"; "–" before any prompt is answered.
    public var medianText: String {
        medianResponseTime.map { "\(secondsText($0, decimals: 2)) s" } ?? "–"
    }

    /// Attempts not right first time (a wrong note first, or a timeout), in the order they happened.
    /// The "In order (check)" summary lists them.
    public var misses: [Attempt] { attempts.filter { !$0.firstRight } }
}

/// A duration in seconds with a fixed number of decimals: "2.31".
func secondsText(_ duration: Duration, decimals: Int) -> String {
    var scale: Int64 = 1
    for _ in 0..<decimals { scale *= 10 }
    let (seconds, attoseconds) = duration.components
    // Round half up to `decimals` places, in whole units of 1 / scale seconds.
    let attosecondsPerUnit = 1_000_000_000_000_000_000 / scale
    let units = seconds * scale + (attoseconds + attosecondsPerUnit / 2) / attosecondsPerUnit
    let whole = units / scale
    guard decimals > 0 else { return "\(whole)" }
    let fraction = String(units % scale)
    return "\(whole).\(String(repeating: "0", count: decimals - fraction.count))\(fraction)"
}
