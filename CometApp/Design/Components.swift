//
//  Components.swift
//  Comet
//
//  The vocabulary every screen is built from, following the desktop app's
//  measurements: square-ish corners, one-pixel borders, flat fills, small
//  type. A card is a panel, not a slab; a button is a rectangle, not a capsule.
//

import SwiftUI

// MARK: - Surfaces

struct CometCard: ViewModifier {
    @Environment(\.comet) private var theme
    var radius: CGFloat = 12
    var lift: CGFloat = 1
    var tinted: Bool = false

    private var corner: CGFloat { min(radius, 14) }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(tinted ? theme.accentSoft.opacity(theme.isDark ? 0.5 : 0.65) : theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: 1)
                    )
            )
            .cometShadow(theme, lift: lift)
    }
}

extension View {
    func cometCard(radius: CGFloat = 12, lift: CGFloat = 1, tinted: Bool = false) -> some View {
        modifier(CometCard(radius: radius, lift: lift, tinted: tinted))
    }

    /// The desktop's raised panel: a surface with a border, no blur.
    func glassPanel(radius: CGFloat = 12) -> some View {
        modifier(GlassPanel(radius: radius))
    }
}

struct GlassPanel: ViewModifier {
    @Environment(\.comet) private var theme
    var radius: CGFloat = 12

    private var corner: CGFloat { min(radius, 14) }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: 1)
                    )
            )
            .cometShadow(theme, lift: 0.7)
    }
}

// MARK: - Buttons

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var haptic: (() -> Void)? = { Haptics.tap() }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { haptic?() }
            }
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var cometPress: PressableStyle { PressableStyle() }
}

/// The desktop's solid accent button.
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
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(type.label(13, weight: .bold))
            }
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, 15)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.accent)
            )
        }
        .buttonStyle(PressableStyle())
    }
}

/// The desktop's bordered secondary button.
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
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(type.label(12.5, weight: .semibold))
            }
            .foregroundStyle(theme.secondary)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PressableStyle())
    }
}

/// A square icon button — the desktop's `.icon-button`.
struct IconOrb: View {
    @Environment(\.comet) private var theme
    let icon: String
    var size: CGFloat = 34
    var tint: Color? = nil
    var solid: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(solid ? theme.onAccent : (tint ?? theme.secondary))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(solid ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.surface))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(solid ? Color.clear : theme.hairline, lineWidth: 1)
                )
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
                .font(type.label(10, weight: .heavy))
                .tracking(1.1)
                .foregroundStyle(theme.tertiary)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(type.mono(10.5, weight: .medium))
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
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(type.label(12, weight: .semibold))
            }
            .foregroundStyle(selected ? theme.accentInk : theme.secondary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? theme.accentSoft : theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? theme.accent.opacity(0.35) : theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle(scale: 0.96))
    }
}

struct Glyph: View {
    @Environment(\.comet) private var theme
    let symbol: String
    var size: CGFloat = 36
    var tint: Color? = nil
    var filled: Bool = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(filled ? theme.onAccent : (tint ?? theme.accent))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(filled ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.accentSoft))
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
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(theme.tertiary)
            Text(title)
                .font(type.title(17))
                .foregroundStyle(theme.ink)
            Text(message)
                .font(type.prose(13))
                .foregroundStyle(theme.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 28)
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
            .offset(y: shown ? 0 : 8)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(Motion.spring.delay(Double(min(index, 12)) * 0.025)) {
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
            .font(type.mono(10.5, weight: .bold))
            .foregroundStyle(theme.accentInk)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 18)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(theme.accentSoft)
            )
    }
}
