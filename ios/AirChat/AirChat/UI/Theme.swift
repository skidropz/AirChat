import Foundation
import SwiftUI

/// Theme + small shared helpers.
enum Theme {
    static func bubbleColor(for color: String, dark: Bool) -> Color {
        let hex = AppConstants.colorHex[color] ?? "#0084FF"
        if color == "white" {
            return dark ? .white : .black
        }
        return Color(hex: hex)
    }

    static func textColor(for color: String, dark: Bool) -> Color {
        color == "white" ? (dark ? .black : .white) : .white
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// Port of the web client's `isEmojiOnly`: standalone emojis render larger.
func isEmojiOnly(_ string: String?) -> Bool {
    guard let s = string?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return false }
    for scalar in s.unicodeScalars {
        let p = scalar.properties.generalCategory
        let isEmojiish =
            p == .otherSymbol || p == .modifierSymbol ||
            (0x1F300...0x1FAFF).contains(scalar.value) ||
            (0x2600...0x27BF).contains(scalar.value) ||
            (0x2190...0x21FF).contains(scalar.value) ||
            scalar.value == 0x200D || // ZWJ
            (0xFE00...0xFE0F).contains(scalar.value) // variation selector
        if !isEmojiish { return false }
    }
    return true
}

/// Great-circle distance in metres (Haversine) — mirrors `calculateDistance`.
func distanceMetres(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let R = 6_371_000.0
    let φ1 = lat1 * .pi / 180, φ2 = lat2 * .pi / 180
    let dφ = (lat2 - lat1) * .pi / 180
    let dλ = (lon2 - lon1) * .pi / 180
    let a = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
    return R * 2 * atan2(sqrt(a), sqrt(1 - a))
}

/// Initial bearing in degrees — mirrors `calculateBearing`.
func bearingDegrees(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let φ1 = lat1 * .pi / 180, φ2 = lat2 * .pi / 180
    let dλ = (lon2 - lon1) * .pi / 180
    let y = sin(dλ) * cos(φ2)
    let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(dλ)
    return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
}
