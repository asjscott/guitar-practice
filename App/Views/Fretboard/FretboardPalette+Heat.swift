import SwiftUI

extension FretboardPalette {
    /// The heatmap tint for a value from 0 to 1: faint amber at 0, strong red at 1.
    /// Values outside 0–1 are clamped.
    static func heat(_ value: Double) -> Color {
        let v = min(max(value, 0), 1)
        return heatHue(v).opacity(0.06 + 0.34 * v * v)
    }

    /// Stops for the small status-bar heat legend, the same hues as `heat(_:)` from 0 to 1,
    /// drawn more opaque so they read against the bar.
    static let heatLegendStops: [Color] = [0, 0.5, 1].map { heatHue($0).opacity(0.35 + 0.65 * $0) }

    private static func heatHue(_ v: Double) -> Color {
        Color(hue: 0.02 + 0.10 * (1 - v), saturation: 0.75, brightness: 1)
    }
}
