//
//  RootView.swift
//  Comet
//
//  The shell. The palette is resolved once here and handed down through the
//  environment; the four surfaces swap underneath a floating dock, and modules
//  and documents arrive over the top of them. There is no bar at the top of any
//  screen — the content starts at the edge and the dock is the only furniture.
//

import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = CometTheme.resolve(paletteID: model.settings.paletteID, colorScheme: colorScheme)
        let type = CometType(scale: min(1.22, model.settings.textScale),
                             bodyScale: min(1.3, model.settings.textScale))

        ZStack(alignment: .bottom) {
            AuroraBackground()

            surfaces
                .transition(.opacity)

            dock
        }
        .environment(\.comet, theme)
        .environment(\.type, type)
        .preferredColorScheme(model.settings.paletteID == "auto" ? nil : (theme.isDark ? .dark : .light))
        .tint(theme.accent)
        .task { model.bootstrap() }
        .fullScreenCover(item: $model.module) { module in
            ModuleHost(module: module)
                .environmentObject(model)
                .environment(\.comet, theme)
                .environment(\.type, type)
        }
        .fullScreenCover(item: $model.openedFile) { entry in
            DocumentHost(entry: entry)
                .environmentObject(model)
                .environment(\.comet, theme)
                .environment(\.type, type)
        }
        .sheet(isPresented: $model.showingNewItem, onDismiss: {
            if let entry = model.pendingOpen {
                model.pendingOpen = nil
                model.open(entry)
            }
        }) {
            NewItemSheet()
                .environmentObject(model)
                .environment(\.comet, theme)
                .environment(\.type, type)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(34)
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $model.showingWorkspacePicker) {
            WorkspaceSheet()
                .environmentObject(model)
                .environment(\.comet, theme)
                .environment(\.type, type)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(34)
                .presentationBackground(.clear)
        }
        .overlay(alignment: .bottom) {
            if model.toast.shown, let message = model.toast.message {
                ToastView(text: message, tone: model.toast.tone)
                    .padding(.bottom, 104)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(6)
            }
        }
        .alert("Comet", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .animation(Motion.spring, value: model.toast.shown)
        .animation(Motion.snappy, value: model.tab)
    }

    @ViewBuilder
    private var surfaces: some View {
        switch model.tab {
        case .today:
            TodayView()
        case .library, .search:
            // Search is the Library's own field expanded, so it shares the
            // screen instead of becoming a fifth place to be.
            LibrarySurface()
        case .studio:
            StudioView()
        case .calendar:
            CalendarScreen()
        case .more:
            MoreScreen()
        }
    }

    private var dock: some View {
        BottomBar(tab: $model.tab,
                  unread: model.unreadTotal,
                  onNew: { model.showingNewItem = true })
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

// MARK: - Module host

struct ModuleHost: View {
    let module: Module
    @EnvironmentObject private var model: CometModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch module {
            case .calendar:
                CalendarScreen(close: close)
            case .feeds:
                FeedsScreen(close: close)
            case .vault:
                VaultScreen(close: close)
            case .tools:
                ToolsScreen(close: close)
            case .sync:
                SyncScreen(close: close)
            case .settings:
                SettingsScreen(close: close)
            }
        }
    }

    private func close() {
        Haptics.tap()
        dismiss()
    }
}

// MARK: - Document host

struct DocumentHost: View {
    let entry: Entry
    @EnvironmentObject private var model: CometModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch entry.kind {
            case .note:
                NoteScreen(entry: entry, close: close)
            case .todo:
                TodoBoardScreen(entry: entry, close: close)
            case .whiteboard:
                WhiteboardScreen(entry: entry, close: close)
            default:
                ViewerScreen(entry: entry, close: close)
            }
        }
    }

    private func close() {
        model.openedFile = nil
        dismiss()
    }
}

// MARK: - New item

/// Quick capture, in the shape of the design: four big tiles that make the
/// thing the moment you touch them, and one row for a file from elsewhere. The
/// name field is optional — leave it alone and Comet names the note, the board
/// or the folder itself, then puts you inside it.
struct NewItemSheet: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var showsImport = false
    @FocusState private var focused: Bool

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetGrabber()

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("QUICK CAPTURE")
                        .font(type.label(9, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(theme.tertiary)
                    Text("Add something new")
                        .font(type.display(26))
                        .foregroundStyle(theme.ink)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.secondary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.raised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(theme.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)

            LazyVGrid(columns: columns, spacing: 12) {
                tile("New note", "Writes as you type", "square.and.pencil", CaptureTint.blue) {
                    create(.note)
                }
                tile("Task board", "Lists and cards", "checklist", CaptureTint.green) {
                    create(.todo)
                }
                tile("Whiteboard", "Anything, anywhere", "scribble.variable", CaptureTint.amber) {
                    create(.whiteboard)
                }
                tile("Folder", "Somewhere to put things", "folder.badge.plus", CaptureTint.violet) {
                    create(.folder)
                }
            }
            .padding(.horizontal, 20)

            Button {
                Haptics.tap()
                showsImport = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.accentInk)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(theme.accentSoft)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import a file")
                            .font(type.prose(14))
                            .foregroundStyle(theme.ink)
                        Text("Anything on this device, PDFs included")
                            .font(type.prose(11))
                            .foregroundStyle(theme.tertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.tertiary)
                }
                .padding(12)
                .cometCard(radius: 14, lift: 0.3)
            }
            .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
            .padding(.horizontal, 20)

            HStack(spacing: 8) {
                Image(systemName: "textformat")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.tertiary)
                TextField("Or name it first (optional)", text: $name)
                    .font(type.prose(13.5))
                    .foregroundStyle(theme.ink)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { create(.note) }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.soft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvas.ignoresSafeArea())
        .fileImporter(isPresented: $showsImport,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                model.importFiles(urls)
            }
            dismiss()
        }
    }

    private func tile(_ title: String, _ detail: String, _ symbol: String,
                      _ tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.press()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(tint.opacity(theme.isDark ? 0.22 : 0.13))
                    )
                Spacer(minLength: 2)
                Text(title)
                    .font(type.title(15))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(type.prose(10.5))
                    .foregroundStyle(theme.tertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
            .padding(13)
            .cometCard(radius: 16, lift: 0.4)
        }
        .buttonStyle(PressableStyle(scale: 0.97, haptic: nil))
    }

    private func title(for kind: EntryKind) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? model.defaultName(for: kind) : trimmed
    }

    private func create(_ kind: EntryKind) {
        let entry: Entry?
        switch kind {
        case .note:
            entry = model.createNote(named: title(for: .note), contents: "# \n\n")
        case .todo, .whiteboard:
            entry = model.createBoard(kind, named: title(for: kind))
        case .folder:
            entry = model.createFolder(named: title(for: .folder))
        default:
            entry = nil
        }
        guard let entry else {
            // The model has put the reason in the root's alert. Close first:
            // an alert raised while a sheet is up belongs to the sheet, and
            // this one is owned by the shell.
            dismiss()
            return
        }
        name = ""
        focused = false
        if entry.isFolder {
            model.pendingOpen = nil
            dismiss()
            model.toast.show("Folder created", tone: .success)
        } else {
            model.pendingOpen = entry
            dismiss()
        }
    }
}

/// The four capture tints, taken from the design's tiles.
enum CaptureTint {
    static let blue = Color(hex: "#5f7f93")
    static let green = Color(hex: "#6e8e7b")
    static let amber = Color(hex: "#b4813f")
    static let violet = Color(hex: "#7775a8")
}

// MARK: - Workspaces

struct WorkspaceSheet: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @Environment(\.dismiss) private var dismiss

    @State private var showsPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetGrabber()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workspaces")
                        .font(type.display(26))
                        .foregroundStyle(theme.ink)
                    Text("A workspace is a folder. Nothing is copied.")
                        .font(type.prose(12.5))
                        .foregroundStyle(theme.tertiary)
                }
                Spacer()
                IconOrb(icon: "xmark", size: 34) { dismiss() }
            }
            .padding(.horizontal, 22)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.workspaces) { ref in
                        Button {
                            Haptics.select()
                            model.open(ref)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Glyph(symbol: "folder.fill", size: 42,
                                      tint: model.currentWorkspace?.id == ref.id ? theme.accent : nil)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ref.name)
                                        .font(type.title(16))
                                        .foregroundStyle(theme.ink)
                                    Text(ref.folderName)
                                        .font(type.mono(11))
                                        .foregroundStyle(theme.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if model.currentWorkspace?.id == ref.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(theme.accent)
                                }
                            }
                            .padding(12)
                            .cometCard(radius: 12, lift: 0.4)
                        }
                        .buttonStyle(PressableStyle(scale: 0.98, haptic: nil))
                        .contextMenu {
                            Button(role: .destructive) {
                                model.remove(ref)
                            } label: {
                                Label("Remove from Comet", systemImage: "minus.circle")
                            }
                        }
                    }

                    Button {
                        Haptics.press()
                        showsPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Glyph(symbol: "plus", size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open another folder")
                                    .font(type.title(16))
                                    .foregroundStyle(theme.ink)
                                Text("On this device or in iCloud Drive")
                                    .font(type.prose(12))
                                    .foregroundStyle(theme.tertiary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .cometCard(radius: 12, lift: 0.4)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98, haptic: nil))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvasGradient.ignoresSafeArea())
        .fileImporter(isPresented: $showsPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                model.addWorkspace(url: url)
            case .failure(let error):
                model.errorMessage = "That folder could not be opened: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Library

/// The Library and the search results are the same screen: the field at the top
/// filters what is underneath, and the bar's Library button brings it back.
struct LibrarySurface: View {
    @EnvironmentObject private var model: CometModel

    var body: some View {
        ZStack {
            FilesView()
                .opacity(model.tab == .library ? 1 : 0)
                .allowsHitTesting(model.tab == .library)
            if model.tab == .search {
                SearchView()
                    .transition(.opacity)
            }
        }
    }
}
