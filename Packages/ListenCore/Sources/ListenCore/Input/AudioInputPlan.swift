/// What to do to bring the input unit in line with what is wanted.
public struct AudioInputPlan: Equatable, Sendable {
    public enum UnitChange: Equatable, Sendable {
        case leave, restart, stop
    }

    public var asksForPermission: Bool
    public var unit: UnitChange

    /// The unit is wanted while a listening screen is open, access is granted and there is an input.
    /// - Parameters:
    ///   - hasTriedToStart: a start has been tried since the last stop, whether or not it worked.
    ///   - choiceChanged: the device or channel isn't the one resolved last time.
    public init(hasListeners: Bool, permission: AudioInputPermission, hasChoice: Bool, choiceChanged: Bool,
                isRunning: Bool, hasTriedToStart: Bool) {
        asksForPermission = hasListeners && permission == .undetermined
        let isWanted = hasListeners && permission == .granted && hasChoice
        unit = if isWanted {
            !isRunning || choiceChanged ? .restart : .leave
        } else {
            hasTriedToStart ? .stop : .leave
        }
    }
}
