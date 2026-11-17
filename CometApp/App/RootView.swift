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
            AuroraBackground(theme: theme)

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
        .sheet(isPresented: $model.showingNewItem) {
            NewItemSheet()
                .environmentObject(model)
                .environment(\.comet, theme)
                .environment(\.type, type)
                .presentationDetents([.height(430), .large])
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
        .overlay {
            if model.showingOrbit {
                OrbitOverlay()
                    .environmentObject(model)
                    .environment(\.comet, theme)
                    .environment(\.type, type)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(5)
            }
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
        .animation(Motion.spring, value: model.showingOrbit)
        .animation(Motion.spring, value: model.toast.shown)
        .animation(Motion.snappy, value: model.tab)
    }

    @ViewBuilder
    private var surfaces: some View {
        switch model.tab {
        case .today:
            TodayView()
        case .files:
            FilesView()
        case .search:
            SearchView()
        case .studio:
            StudioView()
        }
    }

    private var dock: some View {
        BottomDock(tab: $model.tab, unread: model.unreadTotal) {
            model.showingOrbit = true
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
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

// MARK: - Orbit

struct OrbitOverlay: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, theme.isDark ? .dark : .light)
                .overlay(theme.canvas.opacity(theme.isDark ? 0.45 : 0.35))
                .ignoresSafeArea()
                .onTapGesture { close() }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EVERYTHING ELSE")
                                .font(type.label(11, weight: .bold))
                                .tracking(1.6)
                                .foregroundStyle(theme.accent)
                            Text("All surfaces")
                                .font(type.display(32))
                                .foregroundStyle(theme.ink)
                        }
                        Spacer()
                        IconOrb(icon: "xmark", size: 40) { close() }
                    }
                    .padding(.top, 24)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(Module.allCases.enumerated()), id: \.element.id) { index, module in
                            Button {
                                Haptics.press()
                                model.showingOrbit = false
                                model.module = module
                            } label: {
                                moduleCard(module)
                            }
                            .buttonStyle(PressableStyle(scale: 0.97, haptic: nil))
                            .stagger(index)
                        }
                    }

                    Button {
                        Haptics.tap()
                        model.showingOrbit = false
                        model.showingWorkspacePicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Glyph(symbol: "square.stack", size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.workspaceName)
                                    .font(type.label(15, weight: .bold))
                                    .foregroundStyle(theme.ink)
                                Text("Switch workspace")
                                    .font(type.prose(12))
                                    .foregroundStyle(theme.tertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(theme.tertiary)
                        }
                        .padding(14)
                        .cometCard(radius: 22, lift: 0.6)
                    }
                    .buttonStyle(PressableStyle())

                    Text("Comet \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") · local first, no account")
                        .font(type.mono(11))
                        .foregroundStyle(theme.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .task {
            Haptics.press()
        }
    }

    private func moduleCard(_ module: Module) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Glyph(symbol: module.symbol, size: 40)
                Spacer()
                if module == .sync {
                    Text("SOON")
                        .font(type.label(9.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(theme.accent.opacity(0.14)))
                }
                if module == .feeds && model.unreadTotal > 0 {
                    CountBadge(count: model.unreadTotal)
                }
                if module == .vault && model.vault.state == .locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.tertiary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(module.title)
                    .font(type.title(18))
                    .foregroundStyle(theme.ink)
                Text(module.subtitle)
                    .font(type.prose(11.5))
                    .foregroundStyle(theme.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(height: 142, alignment: .top)
        .cometCard(radius: 24, lift: 0.7)
    }

    private func close() {
        Haptics.tap()
        withAnimation(Motion.spring) { model.showingOrbit = false }
    }
}

// MARK: - New item

struct NewItemSheet: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var showsImport = false
    @FocusState private var focused: Bool

    private let options: [(title: String, subtitle: String, symbol: String, action: NewItemAction)] = [
        ("Note", "Markdown, saved as you type", "doc.text", .note),
        ("To-do board", "Lists and cards", "checklist", .todo),
        ("Whiteboard", "Anything, anywhere", "scribble.variable", .whiteboard),
        ("Folder", "Somewhere to put things", "folder.badge.plus", .folder),
        ("Import file", "Anything on this device", "square.and.arrow.down", .importFile),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetGrabber()
            HStack {
                Text("New")
                    .font(type.display(28))
                    .foregroundStyle(theme.ink)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.secondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(theme.raised))
                }
            }
            .padding(.horizontal, 22)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button {
                            Haptics.press()
                            perform(option.action)
                        } label: {
                            HStack(spacing: 13) {
                                Glyph(symbol: option.symbol, size: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title)
                                        .font(type.title(16))
                                        .foregroundStyle(theme.ink)
                                    Text(option.subtitle)
                                        .font(type.prose(12))
                                        .foregroundStyle(theme.tertiary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(theme.tertiary)
                            }
                            .padding(12)
                            .cometCard(radius: 22, lift: 0.4)
                        }
                        .buttonStyle(PressableStyle(scale: 0.98, haptic: nil))
                        .stagger(index)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvasGradient.ignoresSafeArea())
        .fileImporter(isPresented: $showsImport,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                model.importFiles(urls)
            }
            dismiss()
        }
    }

    private enum NewItemAction { case note, todo, whiteboard, folder, importFile }

    private func perform(_ action: NewItemAction) {
        switch action {
        case .note:
            let entry = model.createNote(named: model.defaultName(for: .note), contents: "# \n\n")
            dismiss()
            if let entry { model.open(entry) }
        case .todo:
            if let entry = model.createBoard(.todo, named: model.defaultName(for: .todo)) {
                dismiss()
                model.open(entry)
            }
        case .whiteboard:
            if let entry = model.createBoard(.whiteboard, named: model.defaultName(for: .whiteboard)) {
                dismiss()
                model.open(entry)
            }
        case .folder:
            if model.createFolder(named: model.defaultName(for: .folder)) != nil {
                dismiss()
                model.toast.show("Folder created", tone: .success)
            }
        case .importFile:
            showsImport = true
        }
    }
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
                            .cometCard(radius: 22, lift: 0.4)
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
                        .cometCard(radius: 22, lift: 0.4)
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
            if case .success(let urls) = result, let url = urls.first {
                model.addWorkspace(url: url)
                dismiss()
            }
        }
    }
}
