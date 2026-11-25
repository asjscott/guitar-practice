import AppKit
import SwiftUI

extension View {
    /// Calls `onChange` while active: true when H goes down, false when it is let go. Losing the window, a sheet, and
    /// going away count as letting go. Nothing else in the window sees the key, unless text is being edited.
    func holdsHint(isActive: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        background(HintKeyReader(isActive: isActive, onChange: onChange).accessibilityHidden(true))
    }
}

private struct HintKeyReader: NSViewRepresentable {
    let isActive: Bool
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> HintKeyView { HintKeyView() }

    func updateNSView(_ view: HintKeyView, context: Context) {
        view.onChange = onChange
        view.isActive = isActive
    }

    static func dismantleNSView(_ view: HintKeyView, coordinator: ()) { view.stop() }
}

private final class HintKeyView: NSView {
    /// Going inactive drops the hold without a call: the drill that had it is over.
    var isActive = false { didSet { if !isActive { isHeld = false } } }
    var onChange: (Bool) -> Void = { _ in }
    private var isHeld = false
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard let window else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            // Local monitors run on the main thread.
            let taken = MainActor.assumeIsolated { self?.takes(event) ?? false }
            return taken ? nil : event
        }
        // Outside the key window the key going up may not be seen.
        for name in [NSWindow.didResignKeyNotification, NSWindow.willBeginSheetNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(letGo), name: name, object: window)
        }
    }

    func stop() {
        letGo()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NotificationCenter.default.removeObserver(self)
    }

    private func takes(_ event: NSEvent) -> Bool {
        guard event.charactersIgnoringModifiers?.lowercased() == "h" else { return false }
        if event.type == .keyUp {
            guard isHeld else { return false }
            letGo()
            return true
        }
        guard isActive, event.window === window, window?.attachedSheet == nil, !(window?.firstResponder is NSText),
              event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return false }
        // A hint that ended with H still down waits for it to go down again.
        if !event.isARepeat, !isHeld {
            isHeld = true
            onChange(true)
        }
        return true
    }

    @objc private func letGo() {
        guard isHeld else { return }
        isHeld = false
        onChange(false)
    }
}
