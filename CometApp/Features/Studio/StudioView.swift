//
//  StudioView.swift
//  Comet
//
//  Boards are where a phone stops being a reader. Studio is the shelf they sit
//  on, with a live miniature of each one rather than a generic file icon.
//

import SwiftUI

struct StudioView: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @State private var sheet: ItemSheet?
    @State private var confirmDelete: Entry?

    private var boards: [Entry] { model.boardEntries }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(eyebrow: "Studio",
                             title: "Boards",
                             subtitle: boards.isEmpty ? "Nothing on the bench yet" : "\(boards.count) boards in this workspace") {
                    Menu {
                        Button {
                            if let entry = model.createBoard(.todo, named: model.defaultName(for: .todo)) {
                                model.open(entry)
                            }
                        } label: {
                            Label("To-do board", systemImage: "checklist")
                        }
                        Button {
                            if let entry = model.createBoard(.whiteboard, named: model.defaultName(for: .whiteboard)) {
                                model.open(entry)
                            }
                        } label: {
                            Label("Whiteboard", systemImage: "scribble.variable")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.onAccent)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(theme.accentGradient))
                            .shadow(color: theme.accent.opacity(0.32), radius: 10, y: 5)
                    }
                }

                if boards.isEmpty {
                    EmptyState(icon: "scribble.variable",
                               title: "The bench is clear",
                               message: "Make a to-do board for what needs doing, or a whiteboard for what needs thinking.")
                    PrimaryAction(title: "New board", icon: "plus") {
                        model.showingNewItem = true
                    }
                } else {
                    ForEach(Array(boards.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            model.open(entry)
                        } label: {
                            BoardCard(entry: entry)
                        }
                        .buttonStyle(PressableStyle(scale: 0.98, haptic: nil))
                        .contextMenu {
                            ItemMenu(model: model, entry: entry,
                                     onRename: { sheet = .rename(entry) },
                                     onMove: { sheet = .move(entry) },
                                     onTags: { sheet = .tags(entry) },
                                     onDelete: { confirmDelete = entry })
                        }
                        .stagger(index)
                    }
                }

                footnote
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 132)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $sheet) { item in
            Group {
                switch item {
                case .rename(let entry): RenameSheet(entry: entry).presentationDetents([.height(260)])
                case .move(let entry): MoveSheet(entry: entry).presentationDetents([.medium, .large])
                case .tags(let entry): TagSheet(entry: entry).presentationDetents([.medium, .large])
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
        }
    }

    private var footnote: some View {
        Text("Boards are `.comet-todo` and `.comet-whiteboard` files. Comet on a desktop opens the same files.")
            .font(type.prose(11.5))
            .foregroundStyle(theme.tertiary)
            .padding(.top, 2)
    }
}

// MARK: - Card

struct BoardCard: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    let entry: Entry

    private var text: String { model.readText(entry) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: entry.kind.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .padding(7)
                    .background(Circle().fill(theme.accent.opacity(0.14)))
                Text(entry.kind.displayLabel.uppercased())
                    .font(type.label(10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(theme.tertiary)
                Spacer()
                Text(CometDate.relative(entry.modified))
                    .font(type.mono(10.5))
                    .foregroundStyle(theme.tertiary)
            }

            Text(entry.displayName)
                .font(type.title(19))
                .foregroundStyle(theme.ink)
                .lineLimit(1)

            if entry.kind == .todo {
                todoPreview
            } else {
                whiteboardPreview
            }
        }
        .padding(15)
        .cometCard(radius: 26, lift: 0.6)
    }

    @ViewBuilder
    private var todoPreview: some View {
        let board = TodoDocument.parse(text)
        if let board, !board.tasks.isEmpty {
            VStack(spacing: 6) {
                ForEach(board.tasks.prefix(3)) { task in
                    HStack(spacing: 8) {
                        Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(task.done ? theme.accent : theme.tertiary)
                        Text(task.text.isEmpty ? "Untitled card" : task.text)
                            .font(type.prose(12.5))
                            .foregroundStyle(task.done ? theme.tertiary : theme.secondary)
                            .strikethrough(task.done, color: theme.tertiary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let category = board.categories.first(where: { $0.id == task.categoryID }) {
                            Text(category.title)
                                .font(type.mono(9.5))
                                .foregroundStyle(Color(hex: category.color))
                        }
                    }
                }
                HStack {
                    Text("\(board.openCount) open")
                        .font(type.mono(10.5))
                        .foregroundStyle(theme.tertiary)
                    Spacer()
                    Text("\(board.categories.count) lists")
                        .font(type.mono(10.5))
                        .foregroundStyle(theme.tertiary)
                }
                .padding(.top, 2)
            }
        } else {
            Text("Empty board")
                .font(type.prose(12.5))
                .foregroundStyle(theme.tertiary)
        }
    }

    @ViewBuilder
    private var whiteboardPreview: some View {
        let board = WhiteboardDocument.parse(text)
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.raised.opacity(0.6))
            if let board, !board.items.isEmpty {
                GeometryReader { geometry in
                    let scaleX = geometry.size.width / 900
                    let scaleY = geometry.size.height / 520
                    ForEach(board.items.prefix(8)) { item in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(hex: item.color).opacity(0.85))
                            .frame(width: max(14, item.width * scaleX * 0.5),
                                   height: max(8, item.height * scaleY * 0.4))
                            .position(x: max(8, item.x * scaleX), y: max(8, item.y * scaleY))
                    }
                }
            } else {
                Text("Empty canvas")
                    .font(type.prose(12.5))
                    .foregroundStyle(theme.tertiary)
            }
        }
        .frame(height: 92)
    }
}
