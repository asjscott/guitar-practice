/// A run or session with the metronome panel. Opening it pauses what is going, and closing it goes on with that, unless
/// something else would have paused it since: then `resumesOnPanelClose` is cleared.
@MainActor
protocol MetronomePanelOwner: AnyObject {
    var isPanelOpen: Bool { get }
    var resumesOnPanelClose: Bool { get set }
    /// Going, and not paused.
    var canPause: Bool { get }

    func pause(notice: String?)
    func resume()
}

extension MetronomePanelOwner {
    /// Call it when `isPanelOpen` changes.
    func panelChanged() {
        if isPanelOpen {
            guard canPause else { return }
            pause(notice: nil)
            resumesOnPanelClose = true
        } else if resumesOnPanelClose {
            resumesOnPanelClose = false
            resume()
        }
    }
}
