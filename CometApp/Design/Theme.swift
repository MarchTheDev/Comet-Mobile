//
//  Theme.swift
//  Comet
//
//  One value resolves a palette into everything a view paints with, and travels
//  down the view tree through the environment. No view reaches for a global.
//

import SwiftUI
import UIKit

struct CometTheme {
    let palette: Palette

    var isDark: Bool { palette.isDark }
    var canvas: Color { palette.canvasColor }
    var surface: Color { palette.surfaceColor }
    var soft: Color { palette.softColor }
    var raised: Color { palette.raisedColor }
    var ink: Color { palette.inkColor }
    var secondary: Color { palette.secondaryColor }
    var tertiary: Color { palette.tertiaryColor }
    var accent: Color { palette.accentColor }
    var accentInk: Color { palette.accentInkColor }
    var accentSoft: Color { palette.accentSoftColor }
    var border: Color { palette.borderColor }
    var borderStrong: Color { palette.borderStrongColor }

    /// The desktop app's one line colour.
    var hairline: Color { palette.borderColor }
    var strongLine: Color { palette.borderStrongColor }

    /// Kept for call sites written against the earlier design.
    var accentTwo: Color { palette.accentInkColor }
    var glow: Color { palette.accentSoftColor }

    var shadow: Color { isDark ? Color.black.opacity(0.35) : Color(hex: "#526E7D").opacity(0.10) }
    var softShadow: Color { isDark ? Color.black.opacity(0.25) : Color(hex: "#526E7D").opacity(0.07) }

    /// The desktop has no gradients in its chrome; buttons are flat accent.
    var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent], startPoint: .top, endPoint: .bottom)
    }

    var canvasGradient: LinearGradient {
        LinearGradient(colors: [soft, canvas], startPoint: .top, endPoint: .bottom)
    }

    var onAccent: Color { palette.onAccentColor }

    var glassTint: Color { surface }
    var glassStroke: Color { border }

    static let comet = CometTheme(palette: .comet)

    static func resolve(paletteID: String, colorScheme: ColorScheme) -> CometTheme {
        if paletteID == "auto" {
            return colorScheme == .dark ? CometTheme(palette: .cometDark) : CometTheme(palette: .comet)
        }
        return CometTheme(palette: Palette.named(paletteID))
    }
}

private struct CometThemeKey: EnvironmentKey {
    static let defaultValue = CometTheme.comet
}

extension EnvironmentValues {
    var comet: CometTheme {
        get { self[CometThemeKey.self] }
        set { self[CometThemeKey.self] = newValue }
    }
}

// MARK: - Type

/// The desktop app sets everything in Manrope. The app carries the same font so
/// a note reads the same on both screens, and falls back to the system face if
/// it is ever missing from the bundle.
enum Manrope {
    static let regular = "Manrope-Regular"
    static let medium = "Manrope-Medium"
    static let semibold = "Manrope-SemiBold"
    static let bold = "Manrope-Bold"
    static let extraBold = "Manrope-ExtraBold"

    static let isAvailable: Bool = UIFont(name: regular, size: 12) != nil

    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light: return regular
        case .medium: return medium
        case .semibold: return semibold
        case .bold: return bold
        case .heavy, .black: return extraBold
        default: return regular
        }
    }
}

struct CometType {
    var scale: CGFloat = 1
    var bodyScale: CGFloat = 1

    /// The desktop's interface is compact: 24–35pt for a page title, 14pt for
    /// reading, 9–11pt for labels. The multipliers below keep the call sites
    /// written for the earlier, roomier scale honest without touching them.
    func display(_ size: CGFloat) -> Font {
        font(size * 0.78 * scale, weight: .bold)
    }
    func title(_ size: CGFloat) -> Font {
        font(size * 0.88 * scale, weight: .semibold)
    }
    func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        font(size * scale, weight: weight)
    }
    func prose(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        font(size * 0.94 * bodyScale, weight: weight)
    }
    func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * 0.95 * bodyScale, weight: weight, design: .monospaced)
    }

    func font(_ size: CGFloat, weight: Font.Weight) -> Font {
        if Manrope.isAvailable {
            return .custom(Manrope.name(for: weight), size: size)
        }
        return .system(size: size, weight: weight)
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
        shadow(color: theme.shadow.opacity(0.4 * lift), radius: 14 * lift, x: 0, y: 6 * lift)
    }

    @ViewBuilder
    func hidden(_ condition: Bool) -> some View {
        if condition { self.hidden() } else { self }
    }
}
