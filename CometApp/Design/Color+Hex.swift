//
//  Color+Hex.swift
//  Comet
//
//  Palettes are written as hex strings, the same way Comet's stylesheet writes
//  them, so a palette is data rather than a screenful of Color(red:green:blue:).
//

import SwiftUI

extension Color {
    /// `#RRGGBB` or `#RRGGBBAA`.
    init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
        if text.count == 8 {
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        } else {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        }
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// A colour that fades into the canvas rather than to transparent grey.
    func alpha(_ value: Double) -> Color { opacity(value) }
}
