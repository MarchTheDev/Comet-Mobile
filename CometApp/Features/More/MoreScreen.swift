//
//  MoreScreen.swift
//  Comet
//
//  The drawer, turned inside out. Everything that used to hide behind a
//  hamburger — the boards, the feeds, the vault, the tools, sync, settings,
//  tags, the workspace — is a row on this screen, in one scroll, with the
//  workspace at the top and the local-first promise at the bottom.
//

import SwiftUI

struct MoreScreen: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                workspaceCard
                searchRow
                group("Tools & spaces") { toolsGroup }
                group("Comet") { cometGroup }
                privacyCard
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 132)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            CometMark(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("COMET")
                    .font(type.label(9.5, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(theme.tertiary)
                Text("Everything else")
                    .font(type.display(26))
                    .foregroundStyle(theme.ink)
            }
            Spacer()
        }
    }

    // MARK: Workspace

    private var workspaceCard: some View {
        Button {
            Haptics.tap()
            model.showingWorkspacePicker = true
        } label: {
            HStack(spacing: 12) {
                CometMark(size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.workspaceName)
                        .font(type.title(16))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    Text(model.isWorkspaceReachable
                         ? "On this device · \(model.entries.count) items"
                         : "No folder open · tap to choose one")
                        .font(type.prose(11.5))
                        .foregroundStyle(model.isWorkspaceReachable ? theme.tertiary : theme.accentInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.tertiary)
            }
            .padding(14)
            .cometCard(radius: 14, lift: 0.5)
        }
        .buttonStyle(PressableStyle(scale: 0.98, haptic: nil))
    }

    private var searchRow: some View {
        Button {
            Haptics.tap()
            withAnimation(Motion.snappy) { model.tab = .search }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.tertiary)
                Text("Search anything")
                    .font(type.prose(13.5))
                    .foregroundStyle(theme.tertiary)
                Spacer()
                Text("Names, notes, boards")
                    .font(type.prose(11))
                    .foregroundStyle(theme.tertiary.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.soft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
    }

    // MARK: Groups

    @ViewBuilder
    private var toolsGroup: some View {
        row(title: "Boards & whiteboards",
            detail: boardDetail,
            symbol: "square.grid.2x2",
            tint: PaletteTint.green) {
            model.tab = .studio
        }
        row(title: "Feeds", detail: "RSS, Atom and JSON, read here",
            symbol: "dot.radiowaves.left.and.right", tint: PaletteTint.clay,
            badge: model.unreadTotal > 0 ? "\(model.unreadTotal)" : nil) {
            model.module = .feeds
        }
        row(title: "Passwords", detail: vaultDetail,
            symbol: "lock.shield", tint: PaletteTint.indigo,
            locked: model.vault.state == .locked) {
            model.module = .vault
        }
        row(title: "Tools", detail: "Everything that does arithmetic",
            symbol: "function", tint: PaletteTint.slate) {
            model.module = .tools
        }
        row(title: "Sync", detail: "Across devices, in the next release",
            symbol: "arrow.triangle.2.circlepath", tint: PaletteTint.blue,
            tag: "SOON") {
            model.module = .sync
        }
    }

    @ViewBuilder
    private var cometGroup: some View {
        row(title: "All files", detail: "\(model.entries.count) items in this workspace",
            symbol: "folder", tint: PaletteTint.blue) {
            model.tab = .library
        }
        row(title: "Tags", detail: model.usedTags.isEmpty
                ? "No tags yet" : "\(model.usedTags.count) in use",
            symbol: "tag", tint: PaletteTint.amber) {
            model.tab = .library
        }
        row(title: "Settings", detail: "Palette, type, workspace, backup",
            symbol: "slider.horizontal.3", tint: PaletteTint.slate) {
            model.module = .settings
        }
    }

    private var boardDetail: String {
        let boards = model.boardEntries.count
        return boards == 0 ? "Nothing drawn yet" : "\(boards) board\(boards == 1 ? "" : "s")"
    }

    private var vaultDetail: String {
        switch model.vault.state {
        case .locked: return "Locked with your passphrase"
        case .unlocked: return "\(model.vault.entries.count) entries, unlocked"
        case .empty: return "An encrypted vault, not set up"
        }
    }

    private func group<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(type.label(9.5, weight: .heavy))
                .tracking(1.3)
                .foregroundStyle(theme.tertiary)
                .padding(.leading, 3)
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: 1)
                    )
            )
        }
    }

    private func row(title: String, detail: String, symbol: String, tint: Color,
                     badge: String? = nil, tag: String? = nil, locked: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tint.opacity(theme.isDark ? 0.2 : 0.13))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(type.prose(14.5))
                        .foregroundStyle(theme.ink)
                    Text(detail)
                        .font(type.prose(11))
                        .foregroundStyle(theme.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let badge {
                    Text(badge)
                        .font(type.label(11, weight: .bold))
                        .foregroundStyle(theme.accentInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(theme.accentSoft))
                }
                if let tag {
                    Text(tag)
                        .font(type.label(9, weight: .heavy))
                        .tracking(0.7)
                        .foregroundStyle(theme.accent)
                }
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.tertiary.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                theme.hairline.frame(height: 1).padding(.leading, 58)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.995, haptic: nil))
    }

    // MARK: Footer

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.accentInk)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.accentSoft)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("Private by default")
                    .font(type.title(14))
                    .foregroundStyle(theme.ink)
                Text("No account, no database. Your files stay in the folder you chose, and sync will be opt-in.")
                    .font(type.prose(11.5))
                    .foregroundStyle(theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .cometCard(radius: 14, lift: 0.3, tinted: true)
    }

    private var footer: some View {
        Text("Comet \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") · GPL-3.0")
            .font(type.mono(10.5))
            .foregroundStyle(theme.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }
}

/// The tints the More rows use. They are drawn from the desktop app's own
/// icons, so a vault is the same indigo in both places.
enum PaletteTint {
    static let blue = Color(hex: "#617f91")
    static let green = Color(hex: "#6e8e7b")
    static let clay = Color(hex: "#bd7b50")
    static let indigo = Color(hex: "#6d73a0")
    static let slate = Color(hex: "#778f9d")
    static let amber = Color(hex: "#b48a45")
}
