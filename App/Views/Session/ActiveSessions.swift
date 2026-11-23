import Foundation
import Observation

/// The sessions going, paused included, one per window at most. While there is one, Settings locks the instrument.
@MainActor @Observable
final class ActiveSessions {
    private var ids = Set<UUID>()

    var isAny: Bool { !ids.isEmpty }

    func set(_ id: UUID, isActive: Bool) {
        if isActive { ids.insert(id) } else { ids.remove(id) }
    }
}
