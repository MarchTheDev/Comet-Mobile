//
//  Components.swift
//  Comet
//
//  The vocabulary every screen is built from: cards, chips, glyphs, labels,
//  press behaviour, stagger. Kept small on purpose — a screen that needs a new
//  shape should add it here rather than invent one inline.
//

import SwiftUI

// MARK: - Surfaces

struct CometCard: ViewModifier {
    @Environment(\.comet) private var theme
    var radius: CGFloat = 26
    var lift: CGFloat = 1
    var tinted: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: tinted
                                        ? [theme.accent.opacity(0.22), theme.accentTwo.opacity(0.10)]
                                        : [Color.white.opacity(theme.isDark ? 0.05 : 0.7), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: 1)
                    )
            )
            .cometShadow(theme, lift: lift)
    }
}

extension View {
    func cometCard(radius: CGFloat = 26, lift: CGFloat = 1, tinted: Bool = false) -> some View {
        modifier(CometCard(radius: radius, lift: lift, tinted: tinted))
    }

    /// A translucent slab that lets the aurora through, used for chrome.
    func glassPanel(radius: CGFloat = 26) -> some View {
        modifier(GlassPanel(radius: radius))
    }
}

struct GlassPanel: ViewModifier {
    @Environment(\.comet) private var theme
    var radius: CGFloat = 26

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, theme.isDark ? .dark : .light)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(theme.glassTint.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(theme.glassStroke, lineWidth: 1)
                    )
            )
            .shadow(color: theme.shadow, radius: 24, x: 0, y: 12)
    }
}

// MARK: - Buttons

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var haptic: (() -> Void)? = { Haptics.tap() }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { haptic?() }
            }
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var cometPress: PressableStyle { PressableStyle() }
}

struct PrimaryAction: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    let title: String
    var icon: String? = nil
    var gradient: LinearGradient? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.press()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .semibold)) }
                Text(title).font(type.label(15.5, weight: .bold))
            }
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, 20)
            .frame(height: 50)
            .background(
                Capsule(style: .continuous)
                    .fill(gradient ?? theme.accentGradient)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(theme.isDark ? 0.22 : 0.28), lineWidth: 1)
            )
            .shadow(color: theme.accent.opacity(0.35), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(PressableStyle())
    }
}

struct SoftButton: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(type.label(14, weight: .semibold))
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Capsule(style: .continuous).fill(theme.raised))
            .overlay(Capsule(style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

struct IconOrb: View {
    @Environment(\.comet) private var theme
    let icon: String
    var size: CGFloat = 44
    var tint: Color? = nil
    var solid: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(solid ? theme.onAccent : (tint ?? theme.ink))
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(solid ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.surface))
                )
                .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))
                .shadow(color: theme.softShadow, radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(icon)
    }
}

// MARK: - Labels and chips

struct SectionLabel: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text.uppercased())
                .font(type.label(11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(theme.tertiary)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(type.mono(11.5, weight: .medium))
                    .foregroundStyle(theme.tertiary)
            }
        }
    }
}

struct Chip: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    let title: String
    var icon: String? = nil
    var selected: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(type.label(13, weight: .semibold))
            }
            .foregroundStyle(selected ? theme.onAccent : theme.secondary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.surface))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(selected ? Color.clear : theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle(scale: 0.94))
    }
}

struct Glyph: View {
    @Environment(\.comet) private var theme
    let symbol: String
    var size: CGFloat = 40
    var tint: Color? = nil
    var filled: Bool = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint ?? (filled ? theme.onAccent : theme.accent))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(
                        filled
                            ? AnyShapeStyle(theme.accentGradient)
                            : AnyShapeStyle((tint ?? theme.accent).opacity(theme.isDark ? 0.16 : 0.12))
                    )
            )
    }
}

struct TagDot: View {
    let color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

// MARK: - Empty state

struct EmptyState: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(theme.tertiary)
            Text(title)
                .font(type.title(18))
                .foregroundStyle(theme.ink)
            Text(message)
                .font(type.prose(13.5))
                .foregroundStyle(theme.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Entrance

struct Stagger: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(Motion.spring.delay(Double(min(index, 14)) * 0.035)) {
                        shown = true
                    }
                }
            }
    }
}

extension View {
    func stagger(_ index: Int) -> some View { modifier(Stagger(index: index)) }
}

// MARK: - Misc

struct CometDivider: View {
    @Environment(\.comet) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.hairline)
            .frame(height: 1)
    }
}

struct CountBadge: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(type.mono(11, weight: .semibold))
            .foregroundStyle(theme.secondary)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 20)
            .background(Capsule().fill(theme.raised))
    }
}
