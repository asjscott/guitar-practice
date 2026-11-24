/// A group of drills that train one skill. A session's modules come in this order.
public enum DrillModule: CaseIterable, Hashable, Sendable {
    case notes, scales, triads

    /// "Scales in position".
    public var title: String {
        switch self {
        case .notes: "Fretboard notes"
        case .scales: "Scales in position"
        case .triads: "Triads"
        }
    }

    /// Its share of a session's time relative to the others.
    var weight: Int {
        switch self {
        case .notes: 15
        case .scales, .triads: 20
        }
    }

    /// None of its blocks is shorter, unless there is only one.
    var minimumLength: Duration {
        switch self {
        case .notes: .seconds(90)
        case .scales, .triads: .seconds(180)
        }
    }

    /// Those of one module, in the order given.
    public struct Group<Member> {
        public let module: DrillModule
        public let members: [Member]
    }

    /// Anything that belongs to modules, by module in their order; modules with none are left out.
    public static func groups<Member>(of members: [Member], by module: (Member) -> DrillModule) -> [Group<Member>] {
        allCases.compactMap { candidate in
            let own = members.filter { module($0) == candidate }
            return own.isEmpty ? nil : Group(module: candidate, members: own)
        }
    }
}
