import AppKit
import SwiftUI

/// A key the app acts on wherever the focus is.
enum PlainKey: Hashable {
    case space, `return`, escape
    /// In lower case.
    case character(String)

    fileprivate init?(_ event: NSEvent) {
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return nil }
        switch event.charactersIgnoringModifiers {
        case " ": self = .space
        case "\r", "\u{3}": self = .return
        case "\u{1b}": self = .escape
        case let text?: self = .character(text.lowercased())
        case nil: return nil
        }
    }
}

extension View {
    /// Calls `handle` with keys pressed in this view's window while the view is in it, before the focused control sees
    /// them: a focused list, picker or button would otherwise take Space or Return. A handled key (true) goes no
    /// further. Held-down repeats of a handled key do nothing; a sheet's keys are left to it.
    func onPlainKey(_ handle: @escaping (PlainKey) -> Bool) -> some View {
        background(PlainKeyReader(handle: handle))
    }
}

private struct PlainKeyReader: NSViewRepresentable {
    let handle: (PlainKey) -> Bool

    func makeNSView(context: Context) -> PlainKeyView { PlainKeyView() }
    func updateNSView(_ view: PlainKeyView, context: Context) { view.handle = handle }
    static func dismantleNSView(_ view: PlainKeyView, coordinator: ()) { view.stop() }
}

private final class PlainKeyView: NSView {
    var handle: (PlainKey) -> Bool = { _ in false }
    private var monitor: Any?
    private var handledKey: PlainKey?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return isHandled(event) ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func isHandled(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, window.attachedSheet == nil, let key = PlainKey(event) else { return false }
        if event.isARepeat { return key == handledKey }
        let handled = handle(key)
        handledKey = handled ? key : nil
        return handled
    }
}
