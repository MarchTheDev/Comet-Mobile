//
//  Chrome.swift
//  Comet
//
//  Comet has no navigation bar. Chrome is three floating things and nothing
//  else: a dock that carries the four surfaces, an orb that opens everything
//  else, and a back lens when there is somewhere to go. Content starts at the
//  top of the screen and scrolls under all of them.
//

import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case today
    case files
    case search
    case studio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .files: return "Files"
        case .search: return "Search"
        case .studio: return "Studio"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.horizon"
        case .files: return "square.stack.3d.up"
        case .search: return "sparkle.magnifyingglass"
        case .studio: return "scribble.variable"
        }
    }
}

struct BottomDock: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @Binding var tab: Tab
    var unread: Int
    var onOrbit: () -> Void

    @Namespace private var lens

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { item in
                dockButton(item)
            }

            Rectangle()
                .fill(theme.hairline)
                .frame(width: 1, height: 26)
                .padding(.horizontal, 4)

            Button {
                Haptics.heavy()
                onOrbit()
            } label: {
                ZStack {
                    Circle()
                        .fill(theme.accentGradient)
                        .frame(width: 46, height: 46)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                        .shadow(color: theme.accent.opacity(0.45), radius: 14, x: 0, y: 7)
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.onAccent)
                }
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .accessibilityLabel("All surfaces")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .glassPanel(radius: 34)
    }

    private func dockButton(_ item: Tab) -> some View {
        let selected = tab == item
        return Button {
            guard tab != item else { return }
            Haptics.select()
            withAnimation(Motion.spring) { tab = item }
        } label: {
            HStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 16, weight: .semibold))
                    if item == .studio && unread > 0 {
                        Circle()
                            .fill(theme.accentTwo)
                            .frame(width: 6, height: 6)
                            .offset(x: 5, y: -3)
                    }
                }
                if selected {
                    Text(item.title)
                        .font(type.label(13.5, weight: .bold))
                        .fixedSize()
                }
            }
            .foregroundStyle(selected ? theme.onAccent : theme.secondary)
            .padding(.horizontal, selected ? 15 : 12)
            .frame(height: 44)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(theme.accentGradient)
                        .matchedGeometryEffect(id: "dock-lens", in: lens)
                }
            }
        }
        .buttonStyle(PressableStyle(scale: 0.94, haptic: nil))
        .accessibilityLabel(item.title)
    }
}

// MARK: - Screen header

struct ScreenHeader<Trailing: View>: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(eyebrow.uppercased())
                    .font(type.label(11, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(theme.accent)
                Spacer(minLength: 8)
                trailing()
            }
            Text(title)
                .font(type.display(34))
                .foregroundStyle(theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(type.prose(13.5))
                    .foregroundStyle(theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Floating back

struct FloatingBack: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    var label: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                if let label {
                    Text(label)
                        .font(type.label(13.5, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, label == nil ? 13 : 15)
            .frame(height: 40)
            .glassPanel(radius: 20)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Sheet furniture

struct SheetGrabber: View {
    @Environment(\.comet) private var theme

    var body: some View {
        Capsule()
            .fill(theme.tertiary.opacity(0.45))
            .frame(width: 38, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

struct SheetTitle<Trailing: View>: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(type.title(24))
                    .foregroundStyle(theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(type.prose(13))
                        .foregroundStyle(theme.tertiary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.top, 4)
    }
}

extension SheetTitle where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Toast

@MainActor
final class ToastCenter: ObservableObject {
    enum Tone { case info, success, error }

    @Published var message: String?
    @Published var tone: Tone = .info
    @Published var shown = false
    private var task: Task<Void, Never>?

    func show(_ message: String, tone: Tone = .info) {
        self.message = message
        self.tone = tone
        task?.cancel()
        withAnimation(Motion.spring) { shown = true }
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(Motion.gentle) { self?.shown = false }
            }
        }
    }
}

struct ToastView: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    let text: String
    let tone: ToastCenter.Tone

    private var symbol: String {
        switch tone {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch tone {
        case .info: return theme.accent
        case .success: return Color.green
        case .error: return Color.orange
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(type.label(13.5, weight: .semibold))
                .foregroundStyle(theme.ink)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel(radius: 20)
        .padding(.horizontal, 24)
    }
}
