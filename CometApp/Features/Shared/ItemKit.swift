//
//  ItemKit.swift
//  Comet
//
//  The row, the tile, and the three sheets every list of files needs:
//  rename, move and tags. One row appearance everywhere means a note looks the
//  same in Today, in Files and in a board's attachment list.
//

import SwiftUI
import UIKit

// MARK: - Row

struct EntryRow: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    let entry: Entry
    var showsChevron: Bool = false

    private var meta: String {
        var parts: [String] = [entry.kind.displayLabel]
        if entry.kind == .folder {
            let count = model.children(of: entry.relativePath).count
            parts.append(count == 1 ? "1 item" : "\(count) items")
        } else if entry.size > 0 {
            parts.append(ByteCount.format(entry.size))
        }
        parts.append(CometDate.relative(entry.modified))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Glyph(symbol: entry.kind.symbol, size: 38,
                  tint: entry.kind == .folder ? theme.accentTwo : theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(type.label(15, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    if model.profile.isPinned(entry.relativePath) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.accent)
                    }
                    if model.profile.isFavorite(entry.relativePath) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.yellow.opacity(0.9))
                    }
                }
                HStack(spacing: 6) {
                    Text(meta)
                        .font(type.prose(11.5))
                        .foregroundStyle(theme.tertiary)
                        .lineLimit(1)
                    ForEach(model.profile.tags(for: entry.relativePath).prefix(2)) { tag in
                        HStack(spacing: 3) {
                            TagDot(color: Color(hex: tag.color), size: 6)
                            Text(tag.name)
                                .font(type.prose(10.5))
                                .foregroundStyle(theme.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(theme.raised))
                    }
                }
            }
            Spacer(minLength: 4)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.tertiary)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Folder tile

struct FolderTile: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [theme.accentTwo.opacity(theme.isDark ? 0.34 : 0.22),
                                     theme.accent.opacity(theme.isDark ? 0.16 : 0.10)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 82)
                Image(systemName: "folder.fill")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(theme.accentTwo)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                Text("\(model.children(of: entry.relativePath).count)")
                    .font(type.mono(11, weight: .semibold))
                    .foregroundStyle(theme.secondary)
                    .padding(12)
            }
            Text(entry.displayName)
                .font(type.title(15))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
            Text(CometDate.relative(entry.modified))
                .font(type.mono(10.5))
                .foregroundStyle(theme.tertiary)
        }
        .padding(10)
        .cometCard(radius: 24, lift: 0.5)
    }
}

// MARK: - Context menu

struct ItemMenu: View {
    @ObservedObject var model: CometModel
    let entry: Entry
    var onRename: () -> Void
    var onMove: () -> Void
    var onTags: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button {
            model.open(entry)
        } label: {
            Label("Open", systemImage: "arrow.up.forward.app")
        }
        Button {
            model.togglePin(entry)
        } label: {
            Label(model.profile.isPinned(entry.relativePath) ? "Unpin" : "Pin",
                  systemImage: model.profile.isPinned(entry.relativePath) ? "pin.slash" : "pin")
        }
        Button {
            model.toggleFavorite(entry)
        } label: {
            Label(model.profile.isFavorite(entry.relativePath) ? "Remove favourite" : "Favourite",
                  systemImage: model.profile.isFavorite(entry.relativePath) ? "star.slash" : "star")
        }
        Button {
            onTags()
        } label: {
            Label("Tags", systemImage: "tag")
        }
        Button {
            onRename()
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            onMove()
        } label: {
            Label("Move", systemImage: "folder")
        }
        Divider()
        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Rename

struct RenameSheet: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @Environment(\.dismiss) private var dismiss

    let entry: Entry
    @State private var name: String
    @FocusState private var focused: Bool

    init(entry: Entry) {
        self.entry = entry
        _name = State(initialValue: entry.displayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetGrabber()
            Text("Rename")
                .font(type.display(24))
                .foregroundStyle(theme.ink)
            TextField("Name", text: $name)
                .font(type.prose(17))
                .foregroundStyle(theme.ink)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.raised))
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(commit)
            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }
                    .font(type.label(15, weight: .semibold))
                    .foregroundStyle(theme.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(theme.raised))
                Button("Rename", action: commit)
                    .font(type.label(15, weight: .bold))
                    .foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(theme.accentGradient))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvasGradient.ignoresSafeArea())
        .onAppear { focused = true }
    }

    private func commit() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.rename(entry, to: name)
        dismiss()
    }
}

// MARK: - Move

struct MoveSheet: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @Environment(\.dismiss) private var dismiss

    let entry: Entry

    private var folders: [Entry] {
        model.entries.filter { $0.isFolder && $0.relativePath != entry.relativePath }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetGrabber()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Move")
                        .font(type.display(24))
                        .foregroundStyle(theme.ink)
                    Text("Where should “\(entry.displayName)” go?")
                        .font(type.prose(12.5))
                        .foregroundStyle(theme.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                IconOrb(icon: "xmark", size: 34) { dismiss() }
            }
            ScrollView {
                VStack(spacing: 6) {
                    folderRow(name: model.workspaceName, path: "", depth: 0)
                    ForEach(folders) { folder in
                        folderRow(name: folder.displayName, path: folder.relativePath, depth: folder.depth + 1)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvasGradient.ignoresSafeArea())
    }

    private func folderRow(name: String, path: String, depth: Int) -> some View {
        Button {
            Haptics.select()
            model.move(entry, to: path)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: depth == 0 ? "tray.full" : "folder")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text(name)
                    .font(type.label(14.5, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Spacer()
                if entry.parentPath == path {
                    Text("here")
                        .font(type.mono(10.5))
                        .foregroundStyle(theme.tertiary)
                }
            }
            .padding(.leading, CGFloat(depth) * 14 + 12)
            .padding(.trailing, 12)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface))
        }
        .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
    }
}

// MARK: - Tags

struct TagSheet: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @Environment(\.dismiss) private var dismiss

    let entry: Entry

    @State private var newTagName = ""
    @State private var newTagColor = BoardColor.palette[0]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetGrabber()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tags")
                        .font(type.display(24))
                        .foregroundStyle(theme.ink)
                    Text(entry.displayName)
                        .font(type.prose(12.5))
                        .foregroundStyle(theme.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                IconOrb(icon: "checkmark", size: 34, solid: true) { dismiss() }
            }

            if !model.profile.tags.isEmpty {
                FlowRow(spacing: 8) {
                    ForEach(model.profile.tags) { tag in
                        let selected = model.profile.meta(for: entry.relativePath).tags.contains(tag.id)
                        Button {
                            model.toggleTag(tag, on: entry)
                        } label: {
                            HStack(spacing: 6) {
                                TagDot(color: Color(hex: tag.color))
                                Text(tag.name)
                                    .font(type.label(13, weight: .semibold))
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                            }
                            .foregroundStyle(selected ? theme.onAccent : theme.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(
                                Capsule().fill(selected
                                    ? AnyShapeStyle(Color(hex: tag.color))
                                    : AnyShapeStyle(theme.surface))
                            )
                            .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: selected ? 0 : 1))
                        }
                        .buttonStyle(PressableStyle(scale: 0.95, haptic: nil))
                        .contextMenu {
                            Button(role: .destructive) {
                                model.deleteTag(tag)
                            } label: {
                                Label("Delete tag", systemImage: "trash")
                            }
                        }
                    }
                }
            } else {
                Text("No tags yet. A tag is a colour and a word you can put on anything.")
                    .font(type.prose(13))
                    .foregroundStyle(theme.tertiary)
            }

            CometDivider()

            VStack(alignment: .leading, spacing: 10) {
                Text("NEW TAG")
                    .font(type.label(10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.tertiary)
                HStack(spacing: 10) {
                    TextField("Name", text: $newTagName)
                        .font(type.prose(15))
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(theme.surface))
                    Button {
                        let name = newTagName
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        model.createTag(name: name, color: newTagColor)
                        if let tag = model.profile.tags.last { model.toggleTag(tag, on: entry) }
                        newTagName = ""
                        Haptics.success()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.onAccent)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(theme.accentGradient))
                    }
                    .buttonStyle(PressableStyle())
                }
                HStack(spacing: 8) {
                    ForEach(BoardColor.palette, id: \.self) { hex in
                        Button {
                            Haptics.select()
                            newTagColor = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Circle().strokeBorder(theme.ink.opacity(newTagColor == hex ? 0.8 : 0),
                                                          lineWidth: 2)
                                )
                        }
                        .buttonStyle(PressableStyle(scale: 0.9, haptic: nil))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvasGradient.ignoresSafeArea())
    }
}

// MARK: - Flow layout

/// A wrapping row: chips and tags would otherwise be clipped or scroll sideways.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Formatting

enum ByteCount {
    static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
