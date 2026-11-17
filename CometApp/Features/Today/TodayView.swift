//
//  TodayView.swift
//  Comet
//
//  Today is not a dashboard of widgets; it is the answer to "where was I".
//  It leads with what is pinned, then today's shape (events, unread reading),
//  then what was touched last, then the rest of the app as four doors.
//

import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: Date()).uppercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if !model.pinnedEntries.isEmpty {
                    focus
                }
                quickActions
                agenda
                if model.unreadTotal > 0 || !model.feeds.isEmpty {
                    reading
                }
                recent
                surfaces
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 132)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(dateLine)
                    .font(type.label(11, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(theme.accent)
                Text(CometDate.greeting())
                    .font(type.display(35))
                    .foregroundStyle(theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(model.workspaceName)
                    .font(type.prose(13.5))
                    .foregroundStyle(theme.tertiary)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                model.showingWorkspacePicker = true
            } label: {
                ZStack {
                    Circle()
                        .fill(theme.accentGradient)
                        .frame(width: 44, height: 44)
                    Text(String(model.workspaceName.prefix(1)).uppercased())
                        .font(type.display(19))
                        .foregroundStyle(theme.onAccent)
                }
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                .shadow(color: theme.accent.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Switch workspace")
        }
        .padding(.top, 6)
    }

    // MARK: Focus

    private var focus: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Pinned", trailing: "\(model.pinnedEntries.count)")
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(model.pinnedEntries.prefix(8).enumerated()), id: \.element.id) { index, entry in
                        Button {
                            model.open(entry)
                        } label: {
                            focusCard(entry)
                        }
                        .buttonStyle(PressableStyle(scale: 0.97, haptic: nil))
                        .stagger(index)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func focusCard(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: entry.kind.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.onAccent.opacity(0.85))
                Spacer()
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.onAccent.opacity(0.7))
            }
            Spacer(minLength: 4)
            Text(entry.displayName)
                .font(type.title(18))
                .foregroundStyle(theme.onAccent)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Text(previewLine(for: entry))
                .font(type.prose(12))
                .foregroundStyle(theme.onAccent.opacity(0.78))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .frame(width: 228, height: 152, alignment: .leading)
        .background(
            ZStack {
                theme.accentGradient
                LinearGradient(colors: [Color.black.opacity(0.18), Color.clear], startPoint: .bottom, endPoint: .top)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: theme.accent.opacity(0.3), radius: 18, y: 10)
    }

    private func previewLine(for entry: Entry) -> String {
        guard entry.kind == .note else { return entry.kind.displayLabel }
        let text = model.readText(entry)
        let summary = Markdown.plainSummary(of: text, limit: 90)
        return summary.isEmpty ? "Empty note" : summary
    }

    // MARK: Quick actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            quick("New note", "square.and.pencil") {
                if let entry = model.createNote(named: model.defaultName(for: .note)) {
                    model.open(entry)
                }
            }
            quick("Board", "checklist") {
                if let entry = model.createBoard(.todo, named: model.defaultName(for: .todo)) {
                    model.open(entry)
                }
            }
            quick("Capture", "camera.viewfinder") {
                model.showingNewItem = true
            }
        }
    }

    private func quick(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.press()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text(title)
                    .font(type.label(12.5, weight: .semibold))
                    .foregroundStyle(theme.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .cometCard(radius: 22, lift: 0.45)
        }
        .buttonStyle(PressableStyle(scale: 0.97, haptic: nil))
    }

    // MARK: Agenda

    private var agenda: some View {
        let today = model.events(on: Date())
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Today's shape", trailing: today.isEmpty ? nil : "\(today.count) events")
                Spacer()
                Button {
                    Haptics.tap()
                    model.module = .calendar
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            if today.isEmpty {
                Button {
                    Haptics.tap()
                    model.module = .calendar
                } label: {
                    HStack(spacing: 12) {
                        Glyph(symbol: "sun.max", size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nothing scheduled")
                                .font(type.title(15.5))
                                .foregroundStyle(theme.ink)
                            Text("A clear day. Open the calendar to change that.")
                                .font(type.prose(12))
                                .foregroundStyle(theme.tertiary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .cometCard(radius: 22, lift: 0.45)
                }
                .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(today.enumerated()), id: \.element.id) { index, event in
                        HStack(spacing: 12) {
                            VStack(spacing: 2) {
                                Text(event.time.isEmpty ? "—" : event.time)
                                    .font(type.mono(12, weight: .semibold))
                                    .foregroundStyle(theme.accent)
                                if event.hasTime {
                                    Text("today")
                                        .font(type.mono(9))
                                        .foregroundStyle(theme.tertiary)
                                }
                            }
                            .frame(width: 48)
                            Rectangle()
                                .fill(theme.accent.opacity(0.35))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title)
                                    .font(type.title(15.5))
                                    .foregroundStyle(theme.ink)
                                if !event.notes.isEmpty {
                                    Text(event.notes)
                                        .font(type.prose(11.5))
                                        .foregroundStyle(theme.tertiary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer(minLength: 4)
                        }
                        .padding(.vertical, 10)
                        .frame(minHeight: 52)
                        if index < today.count - 1 { CometDivider() }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .cometCard(radius: 24, lift: 0.5)
            }
        }
    }

    // MARK: Reading

    private var reading: some View {
        Button {
            Haptics.tap()
            model.module = .feeds
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(text: "To read", trailing: model.unreadTotal > 0 ? "\(model.unreadTotal) unread" : nil)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.tertiary)
                }
                let latest = model.unreadArticles.prefix(2)
                if latest.isEmpty {
                    Text("Everything is read. Add a feed to keep it that way.")
                        .font(type.prose(13))
                        .foregroundStyle(theme.tertiary)
                } else {
                    ForEach(Array(latest), id: \.id) { article in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(theme.accentTwo)
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(article.title)
                                    .font(type.label(13.5, weight: .semibold))
                                    .foregroundStyle(theme.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                if let feed = model.feed(for: article.feedID) {
                                    Text(feed.title)
                                        .font(type.mono(10.5))
                                        .foregroundStyle(theme.tertiary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .padding(16)
            .cometCard(radius: 24, lift: 0.5)
        }
        .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
    }

    // MARK: Recent

    @ViewBuilder
    private var recent: some View {
        let recent = model.recentEntries
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Recently opened")
                VStack(spacing: 2) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            model.open(entry)
                        } label: {
                            EntryRow(entry: entry, showsChevron: true)
                        }
                        .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
                        .stagger(index)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .cometCard(radius: 24, lift: 0.5)
            }
        }
    }

    // MARK: Surfaces

    private var surfaces: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Elsewhere")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                surface(.calendar, "\(model.upcomingEvents.count) upcoming")
                surface(.feeds, model.feeds.isEmpty ? "No feeds yet" : "\(model.feeds.count) feeds")
                surface(.vault, model.vault.state == .unlocked ? "Unlocked" : "Locked")
                surface(.tools, "Offline")
            }
        }
    }

    private func surface(_ module: Module, _ detail: String) -> some View {
        Button {
            Haptics.tap()
            model.module = module
        } label: {
            HStack(spacing: 11) {
                Glyph(symbol: module.symbol, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.title)
                        .font(type.title(14.5))
                        .foregroundStyle(theme.ink)
                    Text(detail)
                        .font(type.prose(11))
                        .foregroundStyle(theme.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .cometCard(radius: 20, lift: 0.35)
        }
        .buttonStyle(PressableStyle(scale: 0.98, haptic: nil))
    }

    private var footer: some View {
        HStack {
            Text(model.storageSummary)
                .font(type.mono(11))
                .foregroundStyle(theme.tertiary)
            Spacer()
            Text("LOCAL ONLY")
                .font(type.label(9.5, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(theme.tertiary)
        }
        .padding(.top, 4)
    }
}
