//
//  NoteScreen.swift
//  Comet
//
//  A note is a file and this is a window onto it. Reading is the default, writing
//  is one press away, and saving happens on its own: there is no Save button to
//  forget. The formatting bar edits around the cursor, and every edit lands in
//  the same Markdown the desktop app opens.
//

import SwiftUI
import UIKit
import PhotosUI

struct NoteScreen: View {
    let entry: Entry
    let close: () -> Void

    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @State private var text: String
    @State private var title: String
    @State private var mode: Mode = .read
    @State private var saveState: SaveState = .saved
    @State private var saveTask: Task<Void, Never>?
    @State private var bridge = EditorBridge()
    @State private var photo: PhotosPickerItem?
    @State private var showsRename = false
    @State private var confirmDelete = false

    private enum Mode { case read, write }
    private enum SaveState { case saved, saving, failed }

    init(entry: Entry, close: @escaping () -> Void) {
        self.entry = entry
        self.close = close
        _text = State(initialValue: "")
        _title = State(initialValue: entry.displayName)
        _mode = State(initialValue: .read)
    }

    private var words: Int {
        text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }

    private var readingMinutes: Int {
        max(1, Int((Double(words) / 220).rounded(.up)))
    }

    var body: some View {
        ZStack(alignment: .top) {
            theme.canvasGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleBlock
                    if mode == .read {
                        MarkdownView(text: text,
                                     bodySize: 16.5 + (model.settings.textScale - 1) * 6,
                                     onToggleTask: toggleTask,
                                     imageURL: imageURL)
                            .padding(.bottom, 8)
                    } else {
                        MarkdownTextView(text: $text,
                                         fontSize: model.settings.editorFontSize,
                                         spellcheck: model.settings.spellcheck,
                                         theme: theme,
                                         bridge: bridge)
                            .frame(minHeight: 320)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 66)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                controls
            }

            topChrome
        }
        .task {
            text = model.readText(entry)
        }
        .onChange(of: text) { _, newValue in
            scheduleSave(newValue)
        }
        .onDisappear {
            saveTask?.cancel()
            model.saveText(text, at: entry)
            if title.trimmingCharacters(in: .whitespaces).isEmpty == false, title != entry.displayName {
                model.rename(entry, to: title)
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let name = "Image-\(Int(Date().timeIntervalSince1970)).jpg"
                    let folder = entry.parentPath
                    if let imported = model.importImage(data: data, name: name, folder: folder) {
                        bridge.insert("\n![](" + imported.name + ")\n")
                        if mode == .read { mode = .write }
                        model.toast.show("Image added", tone: .success)
                    }
                }
                photo = nil
            }
        }
        .sheet(isPresented: $showsRename) {
            RenameSheet(entry: entry)
                .environmentObject(model)
                .environment(\.comet, theme)
                .environment(\.type, type)
                .presentationDetents([.height(260)])
                .presentationBackground(.clear)
                .presentationCornerRadius(34)
        }
        .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.delete(entry)
                close()
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("It goes to the Trash on this device.")
        }
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Untitled", text: $title)
                .font(type.display(31))
                .foregroundStyle(theme.ink)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .onSubmit { model.rename(entry, to: title) }
                .accessibilityLabel("Note title")

            HStack(spacing: 8) {
                Image(systemName: saveState == .saved ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(saveState == .failed ? Color.orange : theme.tertiary)
                Text(saveLabel)
                    .font(type.mono(10.5))
                    .foregroundStyle(saveState == .failed ? Color.orange : theme.tertiary)
                Text("·").foregroundStyle(theme.tertiary)
                Text("\(words) \(words == 1 ? "word" : "words")")
                    .font(type.mono(10.5))
                    .foregroundStyle(theme.tertiary)
                Text("·").foregroundStyle(theme.tertiary)
                Text("\(readingMinutes) min read")
                    .font(type.mono(10.5))
                    .foregroundStyle(theme.tertiary)
                Spacer()
            }
        }
    }

    private var saveLabel: String {
        switch saveState {
        case .saved: return "Saved"
        case .saving: return "Saving…"
        case .failed: return "Not saved"
        }
    }

    // MARK: Chrome

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
            .accessibilityLabel("Close note")

            Spacer()

            HStack(spacing: 8) {
                Button {
                    model.togglePin(entry)
                } label: {
                    Image(systemName: model.profile.isPinned(entry.relativePath) ? "pin.fill" : "pin")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(model.profile.isPinned(entry.relativePath) ? theme.accent : theme.ink)
                        .frame(width: 40, height: 40)
                        .glassPanel(radius: 20)
                }
                .buttonStyle(PressableStyle())

                Menu {
                    Button {
                        model.toggleFavorite(entry)
                    } label: {
                        Label(model.profile.isFavorite(entry.relativePath) ? "Remove favourite" : "Favourite",
                              systemImage: "star")
                    }
                    Button {
                        showsRename = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        UIPasteboard.general.string = text
                        model.toast.show("Copied the note", tone: .success)
                    } label: {
                        Label("Copy text", systemImage: "doc.on.doc")
                    }
                    if let url = model.temporaryFile(name: entry.displayName + ".md", contents: text) {
                        ShareLink(item: url) {
                            Label("Share as Markdown", systemImage: "square.and.arrow.up")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
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

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            if mode == .write {
                formatBar
            }
            HStack(spacing: 8) {
                modeSwitch
                Spacer(minLength: 8)
                if mode == .write {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Image(systemName: "photo")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.ink)
                            .frame(width: 44, height: 44)
                            .glassPanel(radius: 22)
                    }
                } else {
                    Button {
                        Haptics.press()
                        withAnimation(Motion.spring) { mode = .write }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { bridge.focus() }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .bold))
                            Text("Edit")
                                .font(type.label(14, weight: .bold))
                        }
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(Capsule().fill(theme.accentGradient))
                        .shadow(color: theme.accent.opacity(0.35), radius: 12, y: 6)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 6)
        }
        .background(
            LinearGradient(colors: [theme.canvas.opacity(0), theme.canvas.opacity(0.92)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
    }

    private var modeSwitch: some View {
        HStack(spacing: 3) {
            modeButton("Read", symbol: "book", target: .read)
            modeButton("Write", symbol: "pencil.line", target: .write)
        }
        .padding(4)
        .glassPanel(radius: 24)
    }

    private func modeButton(_ label: String, symbol: String, target: Mode) -> some View {
        Button {
            guard mode != target else { return }
            Haptics.select()
            withAnimation(Motion.spring) { mode = target }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(type.label(13, weight: .semibold))
            }
            .foregroundStyle(mode == target ? theme.onAccent : theme.secondary)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background {
                if mode == target {
                    Capsule().fill(theme.accentGradient)
                }
            }
        }
        .buttonStyle(PressableStyle(scale: 0.95, haptic: nil))
    }

    private var formatBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                formatButton("bold", "Bold") { bridge.wrap("**") }
                formatButton("italic", "Italic") { bridge.wrap("*") }
                formatButton("strikethrough", "Strikethrough") { bridge.wrap("~~") }
                formatButton("chevron.left.forwardslash.chevron.right", "Code") { bridge.wrap("`") }
                formatButton("textformat.size", "Heading") { bridge.toggleLinePrefix("## ") }
                formatButton("list.bullet", "List") { bridge.toggleLinePrefix("- ") }
                formatButton("checklist", "Task") { bridge.toggleLinePrefix("- [ ] ") }
                formatButton("text.quote", "Quote") { bridge.toggleLinePrefix("> ") }
                formatButton("link", "Link") { bridge.insert("[text](https://)") }
                formatButton("minus", "Divider") { bridge.insert("\n---\n") }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func formatButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.ink)
                .frame(width: 40, height: 40)
                .background(Circle().fill(theme.surface))
                .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.92, haptic: nil))
        .accessibilityLabel(label)
    }

    // MARK: Saving

    private func scheduleSave(_ value: String) {
        saveTask?.cancel()
        saveState = .saving
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            let ok = model.saveText(value, at: entry)
            saveState = ok ? .saved : .failed
        }
    }

    // MARK: Reading helpers

    private func toggleTask(_ label: String, _ done: Bool) {
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isBox = trimmed.hasPrefix("- [ ] ") || trimmed.lowercased().hasPrefix("- [x] ")
            guard isBox else { continue }
            let content = String(trimmed.dropFirst(6))
            if Markdown.plainText(Markdown.inline(content)) == label {
                var replaced = lines
                replaced[index] = (done ? "- [ ] " : "- [x] ") + content
                text = replaced.joined(separator: "\n")
                Haptics.select()
                return
            }
        }
    }

    private func imageURL(_ source: String) -> URL? {
        if source.hasPrefix("http://") || source.hasPrefix("https://") { return URL(string: source) }
        if source.hasPrefix("file://") { return URL(string: source) }
        let decoded = source.removingPercentEncoding ?? source
        var parts = entry.parentPath.components(separatedBy: "/").filter { !$0.isEmpty }
        for piece in decoded.components(separatedBy: "/") {
            if piece.isEmpty || piece == "." { continue }
            if piece == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(piece)
        }
        let path = parts.joined(separator: "/")
        return model.entry(at: path)?.url
    }
}
