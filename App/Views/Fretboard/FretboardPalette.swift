import SwiftUI

/// Colours for the neck and its dots (from the A2 prototype). Shared by the fretboard view
/// and anything that explains it (header chips, status-bar legend).
enum FretboardPalette {
    static let woodTop = Color(red: 0.24, green: 0.16, blue: 0.11)
    static let woodBottom = Color(red: 0.17, green: 0.11, blue: 0.08)
    static let binding = Color(red: 0.93, green: 0.89, blue: 0.80)
    static let bone = Color(red: 0.95, green: 0.92, blue: 0.84)
    static let pearl = Color(red: 0.92, green: 0.91, blue: 0.87)
    static let fretWire = Color(red: 0.80, green: 0.80, blue: 0.78)
    static let woundString = Color(red: 0.82, green: 0.72, blue: 0.55)
    static let plainString = Color(red: 0.88, green: 0.88, blue: 0.88)

    static let root = Color(red: 0.91, green: 0.45, blue: 0.23)
    static let tone = Color(red: 0.23, green: 0.51, blue: 0.96)

    static func color(for role: FretboardDiagram.Role) -> Color {
        switch role {
        case .root: root
        case .tone: tone
        }
    }
}
