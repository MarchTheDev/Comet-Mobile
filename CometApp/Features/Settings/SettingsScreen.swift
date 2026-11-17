//
//  SettingsScreen.swift
//  Comet
//
//  Appearance, type, behaviour and the workspace. Everything here changes
//  something immediately — there is no Apply, and nothing pretends to work.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsScreen: View {
    let close: () -> Void

    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @State private var showingWorkspacePicker = false

    var body: some View {
        ZStack(alignment: .top) {
            ModuleBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ModuleHeader(eyebrow: "Comet", title: "Settings", subtitle: "Palette, type, workspace", close: close)

                    paletteCard
                    typeCard
                    behaviourCard
                    workspaceCard
                    syncCard
                    aboutCard
                    resetButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .fileImporter(isPresented: $showingWorkspacePicker, allowedContentTypes: [.folder]) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.addWorkspace(url: url)
            }
        }
    }

    // MARK: Palette

    private var paletteCard: some View {
        card("Appearance") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Palette.all) { palette in
                    Button {
                        Haptics.select()
                        withAnimation(Motion.gentle) { model.settings.paletteID = palette.id }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(colors: [palette.accentColor, palette.accentTwoColor],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                                    .frame(width: 40, height: 40)
                                Circle()
                                    .strokeBorder(palette.canvasColor.opacity(0.55), lineWidth: 4)
                                    .frame(width: 28, height: 28)
                                if model.settings.paletteID == palette.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(palette.accentColor)
                                }
                            }
                            .overlay(Circle().strokeBorder(theme.ink.opacity(model.settings.paletteID == palette.id ? 0.5 : 0),
                                                           lineWidth: 2))
                            Text(palette.name)
                                .font(type.label(10.5, weight: .semibold))
                                .foregroundStyle(model.settings.paletteID == palette.id ? theme.ink : theme.tertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(model.settings.paletteID == palette.id ? theme.raised : Color.clear)
                        )
                    }
                    .buttonStyle(PressableStyle(scale: 0.95, haptic: nil))
                }
            }
        }
    }

    // MARK: Type

    private var typeCard: some View {
        card("Reading and writing") {
            slider("Text size", value: $model.settings.textScale, range: 0.85...1.25, step: 0.05,
                   label: "\(Int(model.settings.textScale * 100))%")
            slider("Editor type", value: $model.settings.editorFontSize, range: 13...22, step: 1,
                   label: "\(Int(model.settings.editorFontSize)) pt")
            toggle("Check spelling", isOn: $model.settings.spellcheck)
            toggle("Word count while writing", isOn: $model.settings.showWordCount)
        }
    }

    // MARK: Behaviour

    private var behaviourCard: some View {
        card("Behaviour") {
            toggle("Haptics", isOn: $model.settings.haptics)
            toggle("Weeks start on Monday", isOn: $model.settings.weekStartsMonday)
            toggle("Reopen the last workspace", isOn: $model.settings.openLastWorkspace)
        }
    }

    // MARK: Workspace

    private var workspaceCard: some View {
        card("Workspace") {
            HStack(spacing: 12) {
                Glyph(symbol: "folder.fill", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.workspaceName)
                        .font(type.title(15))
                        .foregroundStyle(theme.ink)
                    Text(model.currentWorkspace?.pathHint ?? "No folder")
                        .font(type.mono(10))
                        .foregroundStyle(theme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            Text(model.storageSummary)
                .font(type.mono(11))
                .foregroundStyle(theme.tertiary)
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    showingWorkspacePicker = true
                } label: {
                    Text("Open another folder")
                        .font(type.label(13, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Capsule().fill(theme.accent.opacity(0.12)))
                }
                .buttonStyle(PressableStyle())
                Button {
                    Haptics.tap()
                    model.showingWorkspacePicker = true
                    close()
                } label: {
                    Text("Switch")
                        .font(type.label(13, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Capsule().fill(theme.raised))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: Sync

    private var syncCard: some View {
        Button {
            Haptics.tap()
            close()
            model.module = .sync
        } label: {
            card("Sync") {
                HStack(spacing: 12) {
                    Glyph(symbol: "arrow.triangle.2.circlepath", size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Not switched on yet")
                            .font(type.title(15))
                            .foregroundStyle(theme.ink)
                        Text("The change journal is already recording. Sync arrives in a later update.")
                            .font(type.prose(11.5))
                            .foregroundStyle(theme.tertiary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.tertiary)
                }
            }
        }
        .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
    }

    // MARK: About

    private var aboutCard: some View {
        card("About") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Comet for iOS")
                        .font(type.title(15))
                        .foregroundStyle(theme.ink)
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                        .font(type.mono(10.5))
                        .foregroundStyle(theme.tertiary)
                }
                Spacer()
            }
            Text("A local-first workspace for notes and files, built natively for this device. No account, no server, no telemetry. Comet is GPL-3.0; the desktop app is at github.com/MarchTheDev/Comet.")
                .font(type.prose(11.5))
                .foregroundStyle(theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: URL(string: "https://github.com/MarchTheDev/Comet")!) {
                HStack(spacing: 5) {
                    Text("Comet on GitHub")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(type.label(12, weight: .semibold))
                .foregroundStyle(theme.accent)
            }
        }
    }

    private var resetButton: some View {
        Button {
            Haptics.warning()
            model.settings = CometSettings()
        } label: {
            Text("Reset appearance and behaviour")
                .font(type.label(13, weight: .semibold))
                .foregroundStyle(theme.tertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Pieces

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: title)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cometCard(radius: 24, lift: 0.5)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                        step: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(type.prose(13.5))
                    .foregroundStyle(theme.ink)
                Spacer()
                Text(label)
                    .font(type.mono(11))
                    .foregroundStyle(theme.tertiary)
            }
            Slider(value: value, in: range, step: step)
                .tint(theme.accent)
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(type.prose(13.5))
            .tint(theme.accent)
    }
}
