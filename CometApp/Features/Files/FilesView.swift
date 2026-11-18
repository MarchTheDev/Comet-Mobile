//
//  FilesView.swift
//  Comet
//
//  The folder itself, drawn as a library: a path pill instead of a title bar,
//  folders as tiles because a folder is somewhere you go next, files as rows
//  because a file is something you open, and a filter row that never lies about
//  what is on screen.
//

import SwiftUI

struct FilesView: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @State private var filter: EntryFilter = .all
    @State private var sort: EntrySort = .name
    @State private var tagFilter: String? = nil
    @State private var sheet: ItemSheet?
    @State private var confirmDelete: Entry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                searchPill
                if model.filesPath.isEmpty { summaryRow }
                if !model.filesPath.isEmpty { pathPill }
                filters
                content
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 132)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $sheet) { item in
            Group {
                switch item {
                case .rename(let entry):
                    RenameSheet(entry: entry)
                        .presentationDetents([.height(260)])
                case .move(let entry):
                    MoveSheet(entry: entry)
                        .presentationDetents([.medium, .large])
                case .tags(let entry):
                    TagSheet(entry: entry)
                        .presentationDetents([.medium, .large])
                }
            }
            .environmentObject(model)
            .environment(\.comet, theme)
            .environment(\.type, type)
            .presentationBackground(.clear)
            .presentationCornerRadius(34)
        }
        .confirmationDialog("Delete “\(confirmDelete?.displayName ?? "")”?",
                            isPresented: Binding(get: { confirmDelete != nil },
                                                 set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let entry = confirmDelete { model.delete(entry) }
                confirmDelete = nil
            }
            Button("Keep", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("It goes to the Trash on this device, so it can be recovered from Files.")
        }
    }

    // MARK: Header

    private var folderTitle: String {
        if model.filesPath.isEmpty { return "Library" }
        return model.entry(at: model.filesPath)?.displayName ?? "Library"
    }

    private var header: some View {
        ScreenHeader(eyebrow: "Library",
                     title: folderTitle,
                     subtitle: subtitle) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(EntrySort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Divider()
                    Button {
                        model.showingNewItem = true
                    } label: {
                        Label("New item", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.secondary)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(theme.hairline, lineWidth: 1)
                        )
                }
                Button {
                    Haptics.press()
                    model.showingNewItem = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.onAccent)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.accent)
                        )
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("New item")
            }
        }
    }

    // MARK: Search and counts

    /// The field is a door, not a decoration: tapping it opens the real search
    /// screen, already focused.
    private var searchPill: some View {
        Button {
            Haptics.tap()
            withAnimation(Motion.snappy) { model.tab = .search }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.tertiary)
                Text("Search notes, boards and names")
                    .font(type.prose(13))
                    .foregroundStyle(theme.tertiary)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(theme.soft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
    }

    private var summaryRow: some View {
        let all = model.entries
        let folders = all.filter { $0.isFolder }.count
        let files = all.count - folders
        return HStack(spacing: 0) {
            summaryCell("\(files)", "Files")
            divider
            summaryCell("\(folders)", "Folders")
            divider
            summaryCell("\(model.usedTags.count)", "Tags")
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 1)
                )
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.hairline)
            .frame(width: 1, height: 28)
    }

    private func summaryCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(type.title(19))
                .foregroundStyle(theme.ink)
            Text(label)
                .font(type.label(9.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(theme.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        let all = model.children(of: model.filesPath)
        let folders = all.filter { $0.isFolder }.count
        let files = all.count - folders
        if all.isEmpty { return "Empty folder" }
        var parts: [String] = []
        if folders > 0 { parts.append(folders == 1 ? "1 folder" : "\(folders) folders") }
        if files > 0 { parts.append(files == 1 ? "1 file" : "\(files) files") }
        return parts.joined(separator: " · ")
    }

    // MARK: Path

    private var pathPill: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                Button {
                    Haptics.tap()
                    withAnimation(Motion.snappy) { model.filesPath = "" }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.surface)
                        )
                }
                .buttonStyle(PressableStyle(scale: 0.94, haptic: nil))
                .accessibilityLabel("Back")

                Button {
                    Haptics.tap()
                    withAnimation(Motion.snappy) { model.filesPath = "" }
                } label: {
                    Text("Files")
                        .font(type.label(12.5, weight: .semibold))
                        .foregroundStyle(theme.tertiary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                }
                .buttonStyle(PressableStyle(scale: 0.95, haptic: nil))

                ForEach(model.pathComponents(model.filesPath), id: \.path) { component in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.tertiary)
                    Button {
                        Haptics.tap()
                        withAnimation(Motion.snappy) { model.filesPath = component.path }
                    } label: {
                        Text(component.name)
                            .font(type.label(12.5, weight: component.path == model.filesPath ? .bold : .semibold))
                            .foregroundStyle(component.path == model.filesPath ? theme.accent : theme.secondary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                    }
                    .buttonStyle(PressableStyle(scale: 0.95, haptic: nil))
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
        }
        .scrollIndicators(.hidden)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 1)
                )
        )
    }

    // MARK: Filters

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(EntryFilter.allCases) { option in
                    Chip(title: option.title, icon: option.symbol, selected: filter == option) {
                        withAnimation(Motion.snappy) { filter = option }
                    }
                }
                if !model.usedTags.isEmpty {
                    Rectangle()
                        .fill(theme.hairline)
                        .frame(width: 1, height: 20)
                        .padding(.horizontal, 2)
                    ForEach(model.usedTags, id: \.tag.id) { pair in
                        Button {
                            Haptics.select()
                            withAnimation(Motion.snappy) {
                                tagFilter = tagFilter == pair.tag.id ? nil : pair.tag.id
                            }
                        } label: {
                            HStack(spacing: 6) {
                                TagDot(color: Color(hex: pair.tag.color))
                                Text(pair.tag.name)
                                    .font(type.label(13, weight: .semibold))
                            }
                            .foregroundStyle(tagFilter == pair.tag.id ? theme.onAccent : theme.secondary)
                            .padding(.horizontal, 13)
                            .frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(tagFilter == pair.tag.id
                                        ? AnyShapeStyle(Color(hex: pair.tag.color).opacity(0.18))
                                        : AnyShapeStyle(theme.surface))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(tagFilter == pair.tag.id
                                                  ? Color(hex: pair.tag.color).opacity(0.5)
                                                  : theme.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(PressableStyle(scale: 0.95, haptic: nil))
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Content

    private var visibleEntries: [Entry] {
        var items = model.sortedChildren(of: model.filesPath, filter: filter, sort: sort)
        if let tagFilter {
            items = items.filter { model.profile.meta(for: $0.relativePath).tags.contains(tagFilter) }
        }
        return items
    }

    @ViewBuilder
    private var content: some View {
        let items = visibleEntries
        let folders = items.filter { $0.isFolder }
        let files = items.filter { !$0.isFolder }

        if items.isEmpty {
            emptyState
        } else {
            if !folders.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                        Button {
                            model.openFolder(folder)
                        } label: {
                            FolderTile(entry: folder)
                        }
                        .buttonStyle(PressableStyle(scale: 0.97, haptic: nil))
                        .contextMenu {
                            itemMenu(for: folder)
                        }
                        .stagger(index)
                    }
                }
            }

            if !files.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 4) {
                            Button {
                                model.open(entry)
                            } label: {
                                EntryRow(entry: entry)
                            }
                            .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
                            .contextMenu {
                                itemMenu(for: entry)
                            }
                            Menu {
                                itemMenu(for: entry)
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(theme.tertiary)
                                    .frame(width: 34, height: 34)
                                    .contentShape(Rectangle())
                            }
                        }
                        .stagger(index)
                        if index < files.count - 1 {
                            CometDivider().padding(.leading, 58)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .cometCard(radius: 18, lift: 0.5)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            EmptyState(icon: !model.isWorkspaceReachable ? "folder.badge.questionmark" : (filter == .all ? "folder" : "line.3.horizontal.decrease.circle"),
                       title: !model.isWorkspaceReachable ? "No folder open" : (filter == .all ? "Nothing here yet" : "Nothing matches"),
                       message: !model.isWorkspaceReachable
                        ? "Comet needs a folder it can write to. Open one, or let Comet make its own again."
                        : (filter == .all
                            ? "This folder is empty. Make a note, start a board, or import something."
                            : "Try another filter, or clear the tag."))
            HStack(spacing: 8) {
                if model.isWorkspaceReachable {
                    PrimaryAction(title: "New item", icon: "plus") {
                        model.showingNewItem = true
                    }
                } else {
                    PrimaryAction(title: "Choose folder", icon: "folder") {
                        model.showingWorkspacePicker = true
                    }
                    SoftButton(title: "Repair", icon: "wrench.and.screwdriver") {
                        _ = model.repairWorkspace()
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func itemMenu(for entry: Entry) -> some View {
        ItemMenu(model: model,
                 entry: entry,
                 onRename: { sheet = .rename(entry) },
                 onMove: { sheet = .move(entry) },
                 onTags: { sheet = .tags(entry) },
                 onDelete: { confirmDelete = entry })
    }

    private var footer: some View {
        HStack {
            Text(model.storageSummary)
                .font(type.mono(11))
                .foregroundStyle(theme.tertiary)
            Spacer()
            if let tagFilter, let tag = model.profile.tag(withID: tagFilter) {
                Button {
                    Haptics.tap()
                    withAnimation(Motion.snappy) { self.tagFilter = nil }
                } label: {
                    HStack(spacing: 5) {
                        TagDot(color: Color(hex: tag.color), size: 6)
                        Text(tag.name)
                            .font(type.mono(10.5))
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(theme.secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(theme.surface))
                }
                .buttonStyle(PressableStyle(scale: 0.95, haptic: nil))
            }
        }
        .padding(.top, 2)
    }
}

enum ItemSheet: Identifiable {
    case rename(Entry)
    case move(Entry)
    case tags(Entry)

    var id: String {
        switch self {
        case .rename(let entry): return "rename-" + entry.id
        case .move(let entry): return "move-" + entry.id
        case .tags(let entry): return "tags-" + entry.id
        }
    }
}
