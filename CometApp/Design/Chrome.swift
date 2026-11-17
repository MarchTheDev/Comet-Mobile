//
//  Chrome.swift
//  Comet
//
//  No navigation bar. The desktop app's sidebar becomes a bar at the bottom of
//  the screen: the four surfaces, a way into everything else, and the one
//  accent button that makes something new. Everything is flush, bordered and
//  the same colour as the panels above it.
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
        case .today: return "sun.max"
        case .files: return "folder"
        case .search: return "magnifyingglass"
        case .studio: return "square.grid.2x2"
        }
    }
}

struct BottomDock: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @Binding var tab: Tab
    var unread: Int
    var onOrbit: () -> Void
    var onNew: () -> Void = {}

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { item in
                tabButton(item)
            }

            Spacer(minLength: 6)

            Button {
                Haptics.tap()
                onOrbit()
            } label: {
                Image(systemName: "circle.grid.2x2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.secondary)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.soft)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("All surfaces")

            Button {
                Haptics.press()
                onNew()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 40, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.accent)
                    )
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("New item")
        }
        .padding(.horizontal, 10)
        .padding(.top, 7)
        .padding(.bottom, 5)
        .background(
            theme.surface
                .overlay(alignment: .top) { theme.hairline.frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(_ item: Tab) -> some View {
        let selected = tab == item
        return Button {
            guard tab != item else { return }
            Haptics.select()
            withAnimation(Motion.snappy) { tab = item }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 17, weight: selected ? .semibold : .regular))
                    if item == .studio && unread > 0 {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 5, height: 5)
                            .offset(x: 5, y: -3)
                    }
                }
                Text(item.title)
                    .font(type.label(9.5, weight: selected ? .bold : .medium))
            }
            .foregroundStyle(selected ? theme.accentInk : theme.tertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? theme.accentSoft : Color.clear)
            )
        }
        .buttonStyle(PressableStyle(scale: 0.96, haptic: nil))
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text(eyebrow.uppercased())
                    .font(type.label(10, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(theme.tertiary)
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
                    .font(type.prose(13))
                    .foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
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
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                if let label {
                    Text(label)
                        .font(type.label(12.5, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(theme.secondary)
            .padding(.horizontal, 11)
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

// MARK: - Sheet furniture

struct SheetGrabber: View {
    @Environment(\.comet) private var theme

    var body: some View {
        Capsule()
            .fill(theme.borderStrong)
            .frame(width: 36, height: 4)
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
                        .foregroundStyle(theme.secondary)
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
        case .success: return Color(hex: "#567D68")
        case .error: return Color(hex: "#BD6C65")
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(type.label(12.5, weight: .semibold))
                .foregroundStyle(theme.ink)
                .lineLimit(2)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 1)
                )
                .shadow(color: theme.shadow, radius: 16, x: 0, y: 8)
        )
        .padding(.horizontal, 20)
    }
}
