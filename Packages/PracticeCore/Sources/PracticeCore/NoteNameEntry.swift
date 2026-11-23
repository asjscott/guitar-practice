import TheoryCore

/// A key that can be part of typing a note name.
public enum NoteNameKey: Hashable, Sendable {
    case character(Character)
    /// Backspace.
    case delete
    /// Return.
    case submit
}

/// The note name being typed in a drill answered by typing, and which keys belong to it. Used by free practice and
/// sessions alike: `press` each key, and `follow` the drill after every event.
public struct NoteNameEntry: Hashable, Sendable {
    public enum Press: Hashable, Sendable {
        /// The key is the entry's and must trigger nothing else. Any event is for the drill.
        case taken(DrillEvent?)
        /// The key means whatever it means elsewhere.
        case notTaken
    }

    private var name: NoteName?
    private var promptStart: Duration?

    public init() {}

    /// "F♯"; empty when nothing is typed.
    public var text: String { name?.description ?? "" }

    /// Note letters and accidentals are taken throughout a run, even when no prompt waits for one, so that none typed
    /// late does something else. Return and Backspace are left alone while paused.
    public mutating func press(_ key: NoteNameKey, for drill: any Drill, at now: Duration) -> Press {
        guard drill.kind.usesKeyboard, drill.isRunning else { return .notTaken }
        let accepts = drill.display?.acceptsTypedName == true
        switch key {
        case .character(let character):
            guard NoteName(typed: String(character)) != nil || NoteName(typed: "C\(character)") != nil else { return .notTaken }
            // An accidental on what is there, or a new letter; else (a second accidental) nothing.
            if accepts { name = NoteName(typed: "\(text)\(character)") ?? NoteName(typed: String(character)) ?? name }
            return .taken(nil)
        case .delete:
            guard drill.phase != .paused else { return .notTaken }
            name = name.flatMap { $0.accidental == 0 ? nil : NoteName($0.letter) }
            return .taken(nil)
        case .submit:
            guard drill.phase != .paused else { return .notTaken }
            defer { name = nil }
            return .taken(accepts ? name.map { .typed($0, at: now) } : nil)
        }
    }

    /// Clears what was typed once its prompt no longer waits for it. Call after every drill event.
    public mutating func follow(_ drill: any Drill) {
        if drill.promptStart != promptStart || drill.display?.acceptsTypedName != true { name = nil }
        promptStart = drill.promptStart
    }

    /// The same, as a copy.
    public func following(_ drill: any Drill) -> NoteNameEntry {
        var entry = self
        entry.follow(drill)
        return entry
    }
}
