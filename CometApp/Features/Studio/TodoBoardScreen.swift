//
//  TodoBoardScreen.swift
//  Comet
//
//  A board is lists of cards. On a phone the lists sit side by side and move
//  under a finger; a card is ticked in place, moved from its own menu, and
//  edited in a sheet. It saves into the same `.comet-todo` file the desktop app
//  reads.
//

import SwiftUI
import UIKit

struct TodoBoardScreen: View {
    let entry: Entry
    let close: () -> Void

    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @State private var board = TodoDocument()
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var editing: TodoTask?
    @State private var showingNewList = false
    @State private var newListName = ""
    @State private var confirmingDelete = false

    var body: some View {
        ZStack(alignment: .top) {
            theme.canvasGradient.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if loaded {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(board.categories) { category in
                                TodoColumnView(board: $board, category: category,
                                               onEdit: { editing = $0 })
                                    .frame(width: 282)
                            }
                            unsortedColumn
                            addListCard
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 60)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    ProgressView()
                        .tint(theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            topChrome
        }
        .task { load() }
        .onChange(of: board) { _, newValue in
            scheduleSave(newValue)
        }
        .onDisappear {
            saveTask?.cancel()
            model.saveText(board.serialized(), at: entry)
        }
        .sheet(item: $editing) { task in
            TodoTaskSheet(board: $board, task: task)
                .environmentObject(model)
                .environment(\.comet, theme)
                .environment(\.type, type)
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
                .presentationCornerRadius(34)
        }
        .sheet(isPresented: $showingNewList) {
            newListSheet
                .presentationDetents([.height(250)])
                .presentationBackground(.clear)
                .presentationCornerRadius(34)
        }
        .confirmationDialog("Delete this board?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.delete(entry)
                close()
            }
            Button("Keep", role: .cancel) {}
        }
    }

    private func load() {
        guard !loaded else { return }
        board = TodoDocument.parse(model.readText(entry)) ?? TodoDocument()
        if board.categories.isEmpty {
            board.categories = [TodoCategory(title: "Today", color: BoardColor.palette[0])]
        }
        loaded = true
    }

    private func scheduleSave(_ value: TodoDocument) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            model.saveText(value.serialized(), at: entry)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TO-DO BOARD")
                .font(type.label(10.5, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(theme.accent)
            Text(entry.displayName)
                .font(type.display(30))
                .foregroundStyle(theme.ink)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text("\(board.openCount) open")
                Text("·")
                Text("\(board.tasks.count) cards")
                Text("·")
                Text("\(board.categories.count) lists")
            }
            .font(type.mono(10.5))
            .foregroundStyle(theme.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topChrome: some View {
        HStack {
            Button {
                Haptics.tap()
                close()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .frame(width: 40, height: 40)
                    .glassPanel(radius: 20)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Close board")

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    showingNewList = true
                } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .frame(width: 40, height: 40)
                        .glassPanel(radius: 20)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("New list")

                Menu {
                    Button {
                        Task { await exportMarkdown() }
                    } label: {
                        Label("Export as Markdown", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        model.togglePin(entry)
                    } label: {
                        Label(model.profile.isPinned(entry.relativePath) ? "Unpin" : "Pin", systemImage: "pin")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete board", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.ink)
                        .frame(width: 40, height: 40)
                        .glassPanel(radius: 20)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var unsortedColumn: some View {
        Group {
            let unsorted = board.tasks.filter { $0.categoryID == nil }
            if !unsorted.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Unsorted")
                            .font(type.title(16))
                            .foregroundStyle(theme.ink)
                        Spacer()
                        CountBadge(count: unsorted.count)
                    }
                    ForEach(unsorted) { task in
                        TodoCard(board: $board, task: task, onEdit: { editing = $0 })
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(width: 282, alignment: .top)
                .cometCard(radius: 24, lift: 0.4)
            }
        }
    }

    private var addListCard: some View {
        Button {
            Haptics.press()
            showingNewList = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text("New list")
                    .font(type.label(13.5, weight: .semibold))
                    .foregroundStyle(theme.secondary)
            }
            .frame(width: 140, height: 120)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(theme.hairline)
            )
        }
        .buttonStyle(PressableStyle(scale: 0.97, haptic: nil))
        .padding(.top, 8)
    }

    private var newListSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetGrabber()
            Text("New list")
                .font(type.display(24))
                .foregroundStyle(theme.ink)
            TextField("Name", text: $newListName)
                .font(type.prose(16))
                .foregroundStyle(theme.ink)
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(theme.raised))
            Button {
                let name = newListName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                board.categories.append(TodoCategory(title: name,
                                                     color: BoardColor.palette[board.categories.count % BoardColor.palette.count]))
                newListName = ""
                showingNewList = false
                Haptics.success()
            } label: {
                Text("Add list")
                    .font(type.label(15, weight: .bold))
                    .foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Capsule().fill(theme.accentGradient))
            }
            .buttonStyle(PressableStyle())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvasGradient.ignoresSafeArea())
    }

    private func exportMarkdown() async {
        var lines = ["# " + entry.displayName, ""]
        for category in board.categories {
            lines.append("## " + category.title)
            for task in board.tasks(in: category.id) {
                lines.append("- [\(task.done ? "x" : " ")] " + task.text)
                if !task.notes.isEmpty {
                    lines.append("  " + task.notes.replacingOccurrences(of: "\n", with: "\n  "))
                }
            }
            lines.append("")
        }
        if let url = model.temporaryFile(name: entry.displayName + ".md", contents: lines.joined(separator: "\n")) {
            await MainActor.run {
                let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.keyWindow?.rootViewController?
                    .present(activity, animated: true)
            }
        }
    }
}

// MARK: - Column

struct TodoColumnView: View {
    @Binding var board: TodoDocument
    let category: TodoCategory
    var onEdit: (TodoTask) -> Void

    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @State private var draft = ""
    @State private var adding = false
    @FocusState private var focused: Bool

    private var tasks: [TodoTask] { board.tasks(in: category.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TagDot(color: Color(hex: category.color), size: 8)
                Text(category.title)
                    .font(type.title(16))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                CountBadge(count: tasks.count)
            }

            ForEach(tasks) { task in
                TodoCard(board: $board, task: task, onEdit: onEdit)
            }

            if adding {
                HStack(spacing: 8) {
                    TextField("What needs doing?", text: $draft)
                        .font(type.prose(13.5))
                        .foregroundStyle(theme.ink)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(commit)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surface))
                    Button {
                        commit()
                    } label: {
                        Image(systemName: "return")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.onAccent)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(theme.accent))
                    }
                    .buttonStyle(PressableStyle(scale: 0.9, haptic: nil))
                }
            } else {
                Button {
                    Haptics.tap()
                    adding = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { focused = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add card")
                            .font(type.label(12.5, weight: .semibold))
                    }
                    .foregroundStyle(theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.surface.opacity(0.6)))
                }
                .buttonStyle(PressableStyle(scale: 0.98, haptic: nil))
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 220, alignment: .top)
        .cometCard(radius: 24, lift: 0.4)
    }

    private func commit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            adding = false
            focused = false
            return
        }
        board.addTask(text, categoryID: category.id)
        draft = ""
        Haptics.success()
        if !adding { adding = true }
        focused = true
    }
}

// MARK: - Card

struct TodoCard: View {
    @Binding var board: TodoDocument
    let task: TodoTask
    var onEdit: (TodoTask) -> Void

    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    private var category: TodoCategory? {
        board.categories.first { $0.id == task.categoryID }
    }

    private var doneSubtasks: Int { task.subtasks.filter { $0.done }.count }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button {
                board.toggle(task.id)
                Haptics.select()
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(task.done ? Color(hex: category?.color ?? "#9c9fe1") : theme.tertiary)
            }
            .buttonStyle(PressableStyle(scale: 0.9, haptic: nil))

            VStack(alignment: .leading, spacing: 5) {
                Text(task.text.isEmpty ? "Untitled card" : task.text)
                    .font(type.prose(14, weight: .medium))
                    .foregroundStyle(task.done ? theme.tertiary : theme.ink)
                    .strikethrough(task.done, color: theme.tertiary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                HStack(spacing: 8) {
                    if !task.subtasks.isEmpty {
                        Label("\(doneSubtasks)/\(task.subtasks.count)", systemImage: "checklist")
                            .font(type.mono(10))
                            .foregroundStyle(theme.tertiary)
                    }
                    if !task.notes.isEmpty {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.raised.opacity(task.done ? 0.4 : 1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onEdit(task) }
        .contextMenu {
            Button {
                board.toggle(task.id)
            } label: {
                Label(task.done ? "Mark not done" : "Mark done", systemImage: "checkmark.circle")
            }
            Button {
                onEdit(task)
            } label: {
                Label("Edit card", systemImage: "pencil")
            }
            Menu {
                Button("Unsorted") {
                    board.move(task.id, to: nil)
                }
                ForEach(board.categories) { list in
                    Button(list.title) {
                        board.move(task.id, to: list.id)
                    }
                }
            } label: {
                Label("Move to", systemImage: "arrow.right.circle")
            }
            Divider()
            Button(role: .destructive) {
                board.delete(task.id)
            } label: {
                Label("Delete card", systemImage: "trash")
            }
        }
    }
}

// MARK: - Edit sheet

struct TodoTaskSheet: View {
    @Binding var board: TodoDocument
    let task: TodoTask

    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var notes: String
    @State private var subtasks: [TodoSubtask]
    @State private var categoryID: String?
    @State private var newSubtask = ""

    init(board: Binding<TodoDocument>, task: TodoTask) {
        self._board = board
        self.task = task
        _text = State(initialValue: task.text)
        _notes = State(initialValue: task.notes)
        _subtasks = State(initialValue: task.subtasks)
        _categoryID = State(initialValue: task.categoryID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetGrabber()
            HStack {
                Text("Card")
                    .font(type.display(24))
                    .foregroundStyle(theme.ink)
                Spacer()
                Button {
                    save()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(type.label(14, weight: .bold))
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(Capsule().fill(theme.accentGradient))
                }
                .buttonStyle(PressableStyle())
            }

            TextField("Card text", text: $text, axis: .vertical)
                .font(type.prose(16))
                .foregroundStyle(theme.ink)
                .lineLimit(1...4)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(theme.raised))

            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    Button {
                        Haptics.select()
                        categoryID = nil
                    } label: {
                        chip("Unsorted", selected: categoryID == nil, color: theme.tertiary)
                    }
                    .buttonStyle(PressableStyle(scale: 0.95, haptic: nil))
                    ForEach(board.categories) { list in
                        Button {
                            Haptics.select()
                            categoryID = list.id
                        } label: {
                            chip(list.title, selected: categoryID == list.id, color: Color(hex: list.color))
                        }
                        .buttonStyle(PressableStyle(scale: 0.95, haptic: nil))
                    }
                }
            }
            .scrollIndicators(.hidden)

            VStack(alignment: .leading, spacing: 8) {
                Text("SUBTASKS")
                    .font(type.label(10, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(theme.tertiary)
                ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 8) {
                        Button {
                            subtasks[index].done.toggle()
                            Haptics.select()
                        } label: {
                            Image(systemName: item.done ? "checkmark.square.fill" : "square")
                                .font(.system(size: 14))
                                .foregroundStyle(item.done ? theme.accent : theme.tertiary)
                        }
                        .buttonStyle(PressableStyle(scale: 0.9, haptic: nil))
                        Text(item.text)
                            .font(type.prose(13.5))
                            .foregroundStyle(item.done ? theme.tertiary : theme.ink)
                            .strikethrough(item.done, color: theme.tertiary)
                        Spacer()
                        Button {
                            subtasks.remove(at: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(theme.tertiary)
                        }
                        .buttonStyle(PressableStyle(scale: 0.9, haptic: nil))
                    }
                }
                HStack(spacing: 8) {
                    TextField("Add a subtask", text: $newSubtask)
                        .font(type.prose(13.5))
                        .foregroundStyle(theme.ink)
                        .submitLabel(.done)
                        .onSubmit(addSubtask)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surface))
                    Button(action: addSubtask) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.onAccent)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(theme.accent))
                    }
                    .buttonStyle(PressableStyle(scale: 0.9, haptic: nil))
                }
            }

            TextField("Notes", text: $notes, axis: .vertical)
                .font(type.prose(13.5))
                .foregroundStyle(theme.ink)
                .lineLimit(2...6)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(theme.raised))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvasGradient.ignoresSafeArea())
    }

    private func chip(_ title: String, selected: Bool, color: Color) -> some View {
        HStack(spacing: 6) {
            TagDot(color: color)
            Text(title)
                .font(type.label(12.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(selected ? theme.onAccent : theme.secondary)
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(Capsule().fill(selected ? AnyShapeStyle(color) : AnyShapeStyle(theme.surface)))
    }

    private func addSubtask() {
        let value = newSubtask.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        subtasks.append(TodoSubtask(text: value))
        newSubtask = ""
        Haptics.tap()
    }

    private func save() {
        guard let index = board.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        board.tasks[index].text = text
        board.tasks[index].notes = notes
        board.tasks[index].subtasks = subtasks
        board.tasks[index].categoryID = categoryID
    }
}
