import AppKit
import PracticeCore
import SwiftUI

extension View {
    /// While active, offers the window's key presses to `onKey` before anything else sees them: focused controls, the
    /// sidebar's type-to-select, and shortcuts. `onKey` returns true to keep a key from them.
    func typesNoteNames(isActive: Bool, onKey: @escaping (NoteNameKey) -> Bool) -> some View {
        background(NoteNameKeyCatcher(isActive: isActive, onKey: onKey).accessibilityHidden(true))
    }
}

private struct NoteNameKeyCatcher: NSViewRepresentable {
    let isActive: Bool
    let onKey: (NoteNameKey) -> Bool

    func makeNSView(context: Context) -> NoteNameKeyView { NoteNameKeyView() }

    func updateNSView(_ view: NoteNameKeyView, context: Context) {
        view.isActive = isActive
        view.onKey = onKey
    }

    static func dismantleNSView(_ view: NoteNameKeyView, coordinator: ()) { view.isWatching = false }
}

/// Watches its window's key presses while it is in one. A local monitor runs before key equivalents and the first
/// responder; sheets and other windows aren't watched.
private final class NoteNameKeyView: NSView {
    var isActive = false
    var onKey: (NoteNameKey) -> Bool = { _ in false }
    private var monitor: Any?
    /// What became of the key now held, for its repeats.
    private var tookLastKey = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        isWatching = window != nil
    }

    var isWatching: Bool {
        get { monitor != nil }
        set {
            guard newValue != isWatching else { return }
            if newValue {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    // Local monitors run on the main thread.
                    let taken = MainActor.assumeIsolated { self?.takes(event) ?? false }
                    return taken ? nil : event
                }
            } else if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }

    private func takes(_ event: NSEvent) -> Bool {
        guard isActive, event.window === window, let key = NoteNameKey(event) else { return false }
        // A held letter doesn't type itself again: B would become B♭.
        if event.isARepeat, key != .delete { return tookLastKey }
        tookLastKey = onKey(key)
        return tookLastKey
    }
}

private extension NoteNameKey {
    /// Nil for a key with ⌘ or ⌃, or one that types nothing. ⌥ is allowed: # is ⌥3 on some keyboards.
    init?(_ event: NSEvent) {
        guard event.modifierFlags.isDisjoint(with: [.command, .control]) else { return nil }
        switch event.keyCode {
        case 36, 76: self = .submit     // Return, Enter
        case 51: self = .delete
        default:
            guard let characters = event.characters, characters.count == 1, let character = characters.first else { return nil }
            self = .character(character)
        }
    }
}
