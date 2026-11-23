/// Ticks a drill or session about 30 times a second while it goes, so that timeouts and the next prompt happen
/// hands-free.
@MainActor
final class DrillTicker {
    private var task: Task<Void, Never>?

    private static let interval: Duration = .milliseconds(33)

    func start(_ tick: @escaping @MainActor () -> Void) {
        stop()
        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                if Task.isCancelled { return }
                tick()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
