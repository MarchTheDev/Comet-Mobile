//
//  FeedsScreen.swift
//  Comet
//
//  A reader with no service in the middle. Feeds are parsed on the device, the
//  articles keep their read state in the workspace profile, and the reading view
//  is the app's own type on the app's own paper — the feed's HTML is shown, its
//  scripts are not.
//

import SwiftUI
import UniformTypeIdentifiers

struct FeedsScreen: View {
    let close: () -> Void

    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    private enum Filter: Hashable {
        case all
        case saved
        case feed(String)
    }

    @State private var filter: Filter = .all
    @State private var showingAdd = false
    @State private var showingImport = false
    @State private var reading: FeedArticle?

    private var articles: [FeedArticle] {
        switch filter {
        case .all:
            return model.allArticles
        case .saved:
            return model.allArticles.filter { model.profile.isSaved($0.id) }
        case .feed(let id):
            return model.articles(for: id)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ModuleBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ModuleHeader(eyebrow: "Reading",
                                 title: "Feeds",
                                 subtitle: subtitle,
                                 close: close) {
                        HStack(spacing: 8) {
                            Button {
                                Haptics.press()
                                Task { await model.refreshFeeds() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(theme.ink)
                                    .frame(width: 38, height: 38)
                                    .glassPanel(radius: 19)
                                    .rotationEffect(.degrees(model.refreshingFeeds ? 360 : 0))
                                    .animation(model.refreshingFeeds
                                               ? .linear(duration: 1).repeatForever(autoreverses: false)
                                               : .default, value: model.refreshingFeeds)
                            }
                            .buttonStyle(PressableStyle())
                            .disabled(model.feeds.isEmpty)

                            Button {
                                Haptics.press()
                                showingAdd = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(theme.onAccent)
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(theme.accentGradient))
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("Add feed")
                        }
                    }

                    if model.feeds.isEmpty {
                        emptyFeedState
                    } else {
                        feedChips
                        if articles.isEmpty {
                            EmptyState(icon: filter == .saved ? "bookmark" : "newspaper",
                                       title: filter == .saved ? "Nothing saved" : "No articles yet",
                                       message: filter == .saved
                                        ? "Save an article with the bookmark to keep it here."
                                        : "Refresh the feed, or open one and read it.")
                        } else {
                            ArticleList(articles: articles) { article in
                                model.markRead(article)
                                reading = article
                            }
                        }
                        footer
                    }
                }
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.refreshFeeds() }
        }
        .sheet(isPresented: $showingAdd) {
            AddFeedSheet { address in
                await model.addFeed(address)
            }
            .environmentObject(model)
            .environment(\.comet, theme)
            .environment(\.type, type)
            .presentationDetents([.height(300)])
            .presentationBackground(.clear)
            .presentationCornerRadius(34)
        }
        .sheet(item: $reading) { article in
            ArticleScreen(article: article)
                .environmentObject(model)
                .environment(\.comet, theme)
                .environment(\.type, type)
        }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.xml, .text]) { result in
            if case .success(let url) = result {
                model.importOPML(url)
            }
        }
    }

    private var subtitle: String {
        if model.feeds.isEmpty { return "Add a site and read it here" }
        let unread = model.unreadTotal
        return unread == 0 ? "All \(model.allArticles.count) articles read" : "\(unread) unread from \(model.feeds.count) feeds"
    }

    private var emptyFeedState: some View {
        VStack(alignment: .leading, spacing: 14) {
            EmptyState(icon: "dot.radiowaves.left.and.right",
                       title: "No feeds yet",
                       message: "Paste a site's address. Comet looks for the feed and keeps the articles on this device.")
            PrimaryAction(title: "Add a feed", icon: "plus") {
                showingAdd = true
            }
            Button {
                Haptics.tap()
                showingImport = true
            } label: {
                Text("Import an OPML file")
                    .font(type.label(13.5, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
    }

    private var feedChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Chip(title: "All", icon: "square.stack", selected: filter == .all) {
                    filter = .all
                }
                Chip(title: "Saved", icon: "bookmark", selected: filter == .saved) {
                    filter = .saved
                }
                ForEach(model.feeds) { feed in
                    let unread = model.unreadCount(for: feed)
                    Button {
                        Haptics.select()
                        filter = .feed(feed.id)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(feed.color.isEmpty ? theme.accent : Color(hex: feed.color))
                                .frame(width: 7, height: 7)
                            Text(feed.title)
                                .font(type.label(13, weight: .semibold))
                                .lineLimit(1)
                            if unread > 0 {
                                Text("\(unread)")
                                    .font(type.mono(10, weight: .semibold))
                                    .opacity(0.8)
                            }
                        }
                        .foregroundStyle(filter == .feed(feed.id) ? theme.onAccent : theme.secondary)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(
                            Capsule().fill(filter == .feed(feed.id)
                                ? AnyShapeStyle(theme.accentGradient)
                                : AnyShapeStyle(theme.surface))
                        )
                        .overlay(Capsule().strokeBorder(theme.hairline,
                                                        lineWidth: filter == .feed(feed.id) ? 0 : 1))
                    }
                    .buttonStyle(PressableStyle(scale: 0.95, haptic: nil))
                    .contextMenu {
                        Button {
                            filter = .feed(feed.id)
                        } label: {
                            Label("Show this feed", systemImage: "eye")
                        }
                        ShareLink(item: feed.url) {
                            Label("Copy feed address", systemImage: "link")
                        }
                        Divider()
                        Button(role: .destructive) {
                            model.deleteFeed(feed)
                            filter = .all
                        } label: {
                            Label("Remove feed", systemImage: "minus.circle")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            CometDivider()
            HStack(spacing: 14) {
                if let url = model.opmlExportURL() {
                    ShareLink(item: url) {
                        Label("Export OPML", systemImage: "square.and.arrow.up")
                            .font(type.label(12.5, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    }
                }
                Button {
                    Haptics.tap()
                    showingImport = true
                } label: {
                    Label("Import OPML", systemImage: "square.and.arrow.down")
                        .font(type.label(12.5, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            if !model.feedErrors.isEmpty {
                Text("\(model.feedErrors.count) feeds could not be refreshed just now.")
                    .font(type.prose(11.5))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Article list

struct ArticleList: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    let articles: [FeedArticle]
    var onOpen: (FeedArticle) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                Button {
                    Haptics.tap()
                    onOpen(article)
                } label: {
                    row(article)
                }
                .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
                .contextMenu {
                    Button {
                        onOpen(article)
                    } label: {
                        Label("Read", systemImage: "book")
                    }
                    Button {
                        model.markRead(article, read: !model.profile.isRead(article.id))
                    } label: {
                        Label(model.profile.isRead(article.id) ? "Mark unread" : "Mark read",
                              systemImage: "envelope.badge")
                    }
                    Button {
                        model.toggleSaved(article)
                    } label: {
                        Label(model.profile.isSaved(article.id) ? "Remove bookmark" : "Save",
                              systemImage: "bookmark")
                    }
                    if let url = URL(string: article.link), !article.link.isEmpty {
                        ShareLink(item: url) {
                            Label("Open original", systemImage: "safari")
                        }
                    }
                }
                if index < articles.count - 1 {
                    CometDivider().padding(.leading, 44)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .cometCard(radius: 24, lift: 0.5)
        .padding(.horizontal, 20)
    }

    private func row(_ article: FeedArticle) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(model.profile.isRead(article.id) ? theme.tertiary.opacity(0.35) : theme.accent)
                .frame(width: 7, height: 7)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(type.label(14.5, weight: .semibold))
                    .foregroundStyle(model.profile.isRead(article.id) ? theme.secondary : theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                if !article.summary.isEmpty {
                    Text(article.summary)
                        .font(type.prose(11.5))
                        .foregroundStyle(theme.tertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 6) {
                    if let feed = model.feed(for: article.feedID) {
                        Text(feed.title)
                            .font(type.mono(9.5))
                            .foregroundStyle(theme.accent.opacity(0.85))
                    }
                    if let published = article.published {
                        Text("·")
                            .font(type.mono(9.5))
                            .foregroundStyle(theme.tertiary)
                        Text(CometDate.relative(published))
                            .font(type.mono(9.5))
                            .foregroundStyle(theme.tertiary)
                    }
                    if model.profile.isSaved(article.id) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Reader

struct ArticleScreen: View {
    let article: FeedArticle

    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var html: String {
        let body = article.content.isEmpty
            ? "<p>" + article.summary + "</p>"
            : HTML.body(of: article.content)
        let styles = """
        :root { color-scheme: \(theme.isDark ? "dark" : "light"); }
        body { margin: 0; padding: 16px 20px 60px; background: transparent;
               color: \(theme.ink.cssHex);
               font: \(Int(16.5 * model.settings.textScale))px/1.65 -apple-system, sans-serif; }
        a { color: \(theme.accent.cssHex); text-decoration: none; }
        h1, h2, h3, h4 { line-height: 1.25; }
        img, video { max-width: 100%; height: auto; border-radius: 14px; }
        figure { margin: 0 0 1em; }
        blockquote { margin: 0 0 1em; padding-left: 12px; border-left: 3px solid \(theme.accent.cssHex); color: \(theme.secondary.cssHex); }
        pre, code { font-family: ui-monospace, Menlo, monospace; background: \(theme.raised.cssHex); border-radius: 10px; padding: 2px 5px; }
        pre { padding: 12px; overflow-x: auto; }
        table { width: 100%; border-collapse: collapse; }
        td, th { border-bottom: 1px solid \(theme.hairline.cssHex); padding: 8px 6px; text-align: left; }
        """
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>\(styles)</style></head><body>\(body)</body></html>
        """
    }

    var body: some View {
        ZStack(alignment: .top) {
            theme.canvasGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(article.title)
                            .font(type.display(26))
                            .foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            if let feed = model.feed(for: article.feedID) {
                                Text(feed.title)
                                    .font(type.mono(10.5))
                                    .foregroundStyle(theme.accent)
                            }
                            if !article.author.isEmpty {
                                Text("· \(article.author)")
                                    .font(type.mono(10.5))
                                    .foregroundStyle(theme.tertiary)
                            }
                            if let published = article.published {
                                Text("· \(CalendarMath.polite(published))")
                                    .font(type.mono(10.5))
                                    .foregroundStyle(theme.tertiary)
                            }
                        }
                        CometDivider()
                        HTMLView(html: html)
                            .frame(minHeight: 420)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear { model.markRead(article) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .frame(width: 38, height: 38)
                    .glassPanel(radius: 19)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Close article")

            Spacer()

            Button {
                model.toggleSaved(article)
            } label: {
                Image(systemName: model.profile.isSaved(article.id) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.profile.isSaved(article.id) ? theme.accent : theme.ink)
                    .frame(width: 38, height: 38)
                    .glassPanel(radius: 19)
            }
            .buttonStyle(PressableStyle())

            if let url = URL(string: article.link), !article.link.isEmpty {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .frame(width: 38, height: 38)
                        .glassPanel(radius: 19)
                }
                Button {
                    Haptics.tap()
                    openURL(url)
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .frame(width: 38, height: 38)
                        .glassPanel(radius: 19)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

// MARK: - Add feed

struct AddFeedSheet: View {
    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @Environment(\.dismiss) private var dismiss

    var onSubmit: (String) async -> Bool

    @State private var address = ""
    @State private var busy = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetGrabber()
            Text("Add a feed")
                .font(type.display(24))
                .foregroundStyle(theme.ink)
            Text("A site's address is enough — Comet looks for the feed.")
                .font(type.prose(12.5))
                .foregroundStyle(theme.tertiary)

            HStack(spacing: 8) {
                TextField("example.com/feed", text: $address)
                    .font(type.prose(15))
                    .foregroundStyle(theme.ink)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { submit() }
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.raised))
                Button(action: submit) {
                    ZStack {
                        Circle().fill(theme.accentGradient).frame(width: 46, height: 46)
                        if busy {
                            ProgressView().tint(theme.onAccent)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(theme.onAccent)
                        }
                    }
                }
                .buttonStyle(PressableStyle())
                .disabled(busy || address.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvasGradient.ignoresSafeArea())
        .onAppear { focused = true }
    }

    private func submit() {
        guard !busy, !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        busy = true
        let value = address
        Task {
            let added = await onSubmit(value)
            busy = false
            if added { dismiss() }
        }
    }
}
