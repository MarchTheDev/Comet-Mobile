//
//  Theme.swift
//  Comet
//
//  One value resolves a palette into everything a view paints with, and travels
//  down the view tree through the environment. No view reaches for a global.
//

import SwiftUI

struct CometTheme {
    let palette: Palette

    var isDark: Bool { palette.isDark }
    var canvas: Color { palette.canvasColor }
    var surface: Color { palette.surfaceColor }
    var raised: Color { palette.raisedColor }
    var ink: Color { palette.inkColor }
    var secondary: Color { palette.secondaryColor }
    var tertiary: Color { palette.tertiaryColor }
    var accent: Color { palette.accentColor }
    var accentTwo: Color { palette.accentTwoColor }
    var border: Color { palette.borderColor }
    var glow: Color { palette.glowColor }

    /// A hairline that reads on both surfaces.
    var hairline: Color { palette.borderColor }

    var shadow: Color { Color.black.opacity(isDark ? 0.45 : 0.10) }
    var softShadow: Color { Color.black.opacity(isDark ? 0.28 : 0.07) }

    var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentTwo], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var canvasGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [canvas, palette.raisedColor.opacity(0.55), canvas]
                : [canvas, surface, canvas],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Glass tint: the surface colour so materials pick up the palette.
    var glassTint: Color { surface.opacity(isDark ? 0.55 : 0.7) }
    var glassStroke: Color { isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.06) }

    /// Ink for text that sits on the accent colour.
    var onAccent: Color { isDark ? palette.canvasColor : Color.white }

    static let midnight = CometTheme(palette: .midnight)
    static let daylight = CometTheme(palette: .daylight)

    /// Resolve the stored preference against the system appearance.
    static func resolve(paletteID: String, colorScheme: ColorScheme) -> CometTheme {
        if paletteID == "auto" {
            return colorScheme == .dark ? .midnight : .daylight
        }
        return CometTheme(palette: Palette.named(paletteID))
    }
}

private struct CometThemeKey: EnvironmentKey {
    static let defaultValue = CometTheme.midnight
}

extension EnvironmentValues {
    var comet: CometTheme {
        get { self[CometThemeKey.self] }
        set { self[CometThemeKey.self] = newValue }
    }
}

// MARK: - Type

/// Comet's type scale: rounded for anything that names something, plain for
/// reading, monospaced for anything that is really data.
struct CometType {
    var scale: CGFloat = 1
    var bodyScale: CGFloat = 1

    func display(_ size: CGFloat) -> Font {
        .system(size: size * scale, weight: .bold, design: .rounded)
    }
    func title(_ size: CGFloat) -> Font {
        .system(size: size * scale, weight: .semibold, design: .rounded)
    }
    func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size * scale, weight: weight, design: .rounded)
    }
    func prose(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * bodyScale, weight: weight)
    }
    func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * bodyScale, weight: weight, design: .monospaced)
    }
}

private struct CometTypeKey: EnvironmentKey {
    static let defaultValue = CometType()
}

extension EnvironmentValues {
    var type: CometType {
        get { self[CometTypeKey.self] }
        set { self[CometTypeKey.self] = newValue }
    }
}

// MARK: - Small conveniences

extension View {
    /// Fill the width of a row without teaching every call site about frames.
    func fillLeading() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
    }

    func cometShadow(_ theme: CometTheme, lift: CGFloat = 1) -> some View {
        shadow(color: theme.shadow, radius: 22 * lift, x: 0, y: 12 * lift)
    }

    @ViewBuilder
    func hidden(_ condition: Bool) -> some View {
        if condition { self.hidden() } else { self }
    }
}
