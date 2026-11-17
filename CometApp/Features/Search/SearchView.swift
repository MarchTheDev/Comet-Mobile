//
//  SearchView.swift
//  Comet
//
//  One field, no scopes hidden behind a menu: everything in the workspace is
//  searched — names, note text, boards — and the results say where they are.
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @FocusState private var focused: Bool
    @State private var scope: EntryFilter = .all
    @State private var sheet: ItemSheet?
    @State private var confirmDelete: Entry?

    private var results: [SearchHit] {
        model.searchHits.filter { scope.matches($0.entry) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                field
                if model.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    suggestions
                } else if model.searching {
                    loading
                } else if results.isEmpty {
                    EmptyState(icon: "magnifyingglass",
                               title: "No matches",
                               message: "Nothing in this workspace contains “\(model.searchQuery)”.")
                        .padding(.top, 30)
                } else {
                    scopes
                    resultList
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 132)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
        }
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

    // MARK: Field

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.accent)
            TextField("Search notes, boards and files", text: Binding(
                get: { model.searchQuery },
                set: { model.updateSearch($0) }
            ))
            .font(type.prose(16))
            .foregroundStyle(theme.ink)
            .focused($focused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            if !model.searchQuery.isEmpty {
                Button {
                    Haptics.tap()
                    model.updateSearch("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.tertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(focused ? theme.accent.opacity(0.6) : theme.hairline, lineWidth: 1)
                )
        )
        .cometShadow(theme, lift: 0.6)
        .padding(.top, 4)
    }

    private var scopes: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(EntryFilter.allCases) { option in
                    Chip(title: option.title, icon: option.symbol, selected: scope == option) {
                        withAnimation(Motion.snappy) { scope = option }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Suggestions

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.usedTags.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Tags")
                    FlowRow(spacing: 8) {
                        ForEach(model.usedTags, id: \.tag.id) { pair in
                            Button {
                                Haptics.select()
                                model.updateSearch(pair.tag.name)
                            } label: {
                                HStack(spacing: 6) {
                                    TagDot(color: Color(hex: pair.tag.color))
                                    Text(pair.tag.name)
                                        .font(type.label(13, weight: .semibold))
                                        .foregroundStyle(theme.secondary)
                                    Text("\(pair.count)")
                                        .font(type.mono(10.5))
                                        .foregroundStyle(theme.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(Capsule().fill(theme.surface))
                                .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
                            }
                            .buttonStyle(PressableStyle(scale: 0.95, haptic: nil))
                        }
                    }
                }
            }

            if !model.pinnedEntries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Pinned")
                    VStack(spacing: 2) {
                        ForEach(model.pinnedEntries.prefix(4)) { entry in
                            Button { model.open(entry) } label: {
                                EntryRow(entry: entry, showsChevron: true)
                            }
                            .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
                        }
                    }
                    .padding(6)
                    .cometCard(radius: 22, lift: 0.4)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Recently opened")
                let recent = model.recentEntries
                if recent.isEmpty {
                    Text("Open a note and it will be here next time.")
                        .font(type.prose(13))
                        .foregroundStyle(theme.tertiary)
                } else {
                    VStack(spacing: 2) {
                        ForEach(recent) { entry in
                            Button { model.open(entry) } label: {
                                EntryRow(entry: entry, showsChevron: true)
                            }
                            .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
                        }
                    }
                    .padding(6)
                    .cometCard(radius: 22, lift: 0.4)
                }
            }
        }
    }

    private var loading: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(theme.accent)
            Text("Looking through the workspace…")
                .font(type.prose(13))
                .foregroundStyle(theme.tertiary)
        }
        .padding(.top, 24)
    }

    // MARK: Results

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Results", trailing: "\(results.count)")
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, hit in
                    VStack(spacing: 0) {
                        Button {
                            model.open(hit.entry)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Glyph(symbol: hit.entry.kind.symbol, size: 38)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(hit.entry.displayName)
                                        .font(type.label(15, weight: .semibold))
                                        .foregroundStyle(theme.ink)
                                        .lineLimit(1)
                                    Text(hit.snippet.isEmpty ? hit.entry.kind.displayLabel : hit.snippet)
                                        .font(type.prose(12))
                                        .foregroundStyle(theme.tertiary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(hit.entry.relativePath)
                                        .font(type.mono(10))
                                        .foregroundStyle(theme.tertiary.opacity(0.8))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 9)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
                        .contextMenu {
                            ItemMenu(model: model, entry: hit.entry,
                                     onRename: { sheet = .rename(hit.entry) },
                                     onMove: { sheet = .move(hit.entry) },
                                     onTags: { sheet = .tags(hit.entry) },
                                     onDelete: { confirmDelete = hit.entry })
                        }
                        if index < results.count - 1 {
                            CometDivider().padding(.leading, 58)
                        }
                    }
                }
            }
            .padding(4)
            .cometCard(radius: 24, lift: 0.5)
        }
    }
}
