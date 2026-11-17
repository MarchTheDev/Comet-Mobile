//
//  ViewerScreen.swift
//  Comet
//
//  Everything that is not text: images, PDFs, books, audio and video. Each one
//  gets the viewer it deserves rather than being pushed through a browser.
//

import SwiftUI
import AVKit
import PDFKit
import WebKit
import UIKit

struct ViewerScreen: View {
    let entry: Entry
    let close: () -> Void

    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    var body: some View {
        ZStack(alignment: .top) {
            theme.canvasGradient.ignoresSafeArea()

            content
                .padding(.top, 62)
                .padding(.bottom, 16)

            topChrome
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.kind {
        case .image:
            ZoomableImage(url: entry.url)
        case .pdf:
            PDFReader(url: entry.url)
        case .epub:
            EPUBReader(entry: entry)
        case .audio:
            AudioReader(entry: entry)
        case .video:
            VideoReader(entry: entry)
        case .shortcut:
            ShortcutReader(entry: entry)
        default:
            GenericFile(entry: entry)
        }
    }

    private var topChrome: some View {
        HStack(spacing: 10) {
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
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .font(type.label(14, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                Text(entry.kind.displayLabel.uppercased() + (entry.size > 0 ? " · " + ByteCount.format(entry.size) : ""))
                    .font(type.label(9.5, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(theme.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .glassPanel(radius: 20)

            Spacer(minLength: 0)

            ShareLink(item: entry.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .frame(width: 40, height: 40)
                    .glassPanel(radius: 20)
            }

            Menu {
                Button {
                    model.togglePin(entry)
                } label: {
                    Label(model.profile.isPinned(entry.relativePath) ? "Unpin" : "Pin", systemImage: "pin")
                }
                Button {
                    model.toggleFavorite(entry)
                } label: {
                    Label(model.profile.isFavorite(entry.relativePath) ? "Remove favourite" : "Favourite",
                          systemImage: "star")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .frame(width: 40, height: 40)
                    .glassPanel(radius: 20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}

// MARK: - Images

struct ZoomableImage: View {
    let url: URL
    @Environment(\.comet) private var theme

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: geometry.size.width)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in scale = min(6, max(1, lastScale * value)) }
                                .onEnded { _ in lastScale = scale }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(width: lastOffset.width + value.translation.width,
                                                    height: lastOffset.height + value.translation.height)
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(Motion.spring) {
                                if scale > 1 { scale = 1; offset = .zero; lastScale = 1; lastOffset = .zero }
                                else { scale = 2.2; lastScale = 2.2 }
                            }
                        }
                } else {
                    EmptyState(icon: "photo", title: "Image unavailable",
                               message: "This file could not be decoded.")
                }
            }
        }
    }
}

// MARK: - PDF

struct PDFReader: View {
    let url: URL
    @Environment(\.comet) private var theme

    var body: some View {
        PDFKitView(url: url, theme: theme)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 10)
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL
    let theme: CometTheme

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(url: url)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(theme.canvas)
        view.pageShadowsEnabled = true
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.backgroundColor = UIColor(theme.canvas)
        if view.document == nil { view.document = PDFDocument(url: url) }
    }
}

// MARK: - Books

struct EPUBReader: View {
    let entry: Entry

    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @EnvironmentObject private var model: CometModel

    @State private var book: Book?
    @State private var chapterIndex = 0
    @State private var failed = false
    @State private var showChapters = false

    var body: some View {
        Group {
            if let book {
                VStack(spacing: 0) {
                    if chapterIndex < book.chapters.count {
                        HTMLView(html: book.html(for: book.chapters[chapterIndex],
                                                 theme: theme,
                                                 textScale: model.settings.textScale))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .padding(.horizontal, 10)
                    }
                    controls(book)
                }
            } else if failed {
                EmptyState(icon: "book.closed", title: "This book could not be opened",
                           message: "Comet reads EPUB files. This one may be damaged or protected.")
            } else {
                ProgressView().tint(theme.accent)
            }
        }
        .task {
            guard book == nil else { return }
            let url = entry.url
            let loaded = await Task.detached(priority: .userInitiated) { Book.open(url: url) }.value
            if let loaded {
                book = loaded
            } else {
                failed = true
            }
        }
        .sheet(isPresented: $showChapters) {
            if let book {
                VStack(alignment: .leading, spacing: 10) {
                    SheetGrabber()
                    Text("Chapters")
                        .font(type.display(24))
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 20)
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(Array(book.chapters.enumerated()), id: \.element.id) { index, chapter in
                                Button {
                                    Haptics.select()
                                    chapterIndex = index
                                    showChapters = false
                                } label: {
                                    HStack {
                                        Text(chapter.title.isEmpty ? "Chapter \(index + 1)" : chapter.title)
                                            .font(type.prose(14.5, weight: index == chapterIndex ? .semibold : .regular))
                                            .foregroundStyle(index == chapterIndex ? theme.accent : theme.ink)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(index == chapterIndex ? theme.accent.opacity(0.12) : theme.surface))
                                }
                                .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 24)
                    }
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(theme.canvasGradient.ignoresSafeArea())
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
                .presentationCornerRadius(34)
            }
        }
    }

    private func controls(_ book: Book) -> some View {
        HStack(spacing: 10) {
            Button {
                guard chapterIndex > 0 else { return }
                Haptics.tap()
                chapterIndex -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(chapterIndex > 0 ? theme.ink : theme.tertiary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(theme.surface))
            }
            .buttonStyle(PressableStyle(scale: 0.92, haptic: nil))
            .disabled(chapterIndex == 0)

            Button {
                Haptics.tap()
                showChapters = true
            } label: {
                VStack(spacing: 1) {
                    Text(book.title)
                        .font(type.label(12, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    Text("Chapter \(chapterIndex + 1) of \(book.chapters.count)")
                        .font(type.mono(9.5))
                        .foregroundStyle(theme.tertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(theme.surface))
            }
            .buttonStyle(PressableStyle(scale: 0.98, haptic: nil))

            Button {
                guard chapterIndex < book.chapters.count - 1 else { return }
                Haptics.tap()
                chapterIndex += 1
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(chapterIndex < book.chapters.count - 1 ? theme.ink : theme.tertiary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(theme.surface))
            }
            .buttonStyle(PressableStyle(scale: 0.92, haptic: nil))
            .disabled(chapterIndex >= book.chapters.count - 1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
}

struct HTMLView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.showsVerticalScrollIndicator = false
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        view.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - Audio and video

struct VideoReader: View {
    let entry: Entry
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 12) {
            if let player {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.horizontal, 10)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if player == nil { player = AVPlayer(url: entry.url) }
        }
        .onDisappear { player?.pause() }
    }
}

struct AudioReader: View {
    let entry: Entry

    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var progress: Double = 0
    @State private var duration: Double = 0
    @State private var observer: Any?

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 220, height: 220)
                    .shadow(color: theme.accent.opacity(0.4), radius: 40, y: 18)
                Image(systemName: "waveform")
                    .font(.system(size: 62, weight: .light))
                    .foregroundStyle(theme.onAccent)
                    .symbolEffect(.variableColor.iterative, isActive: playing)
            }
            Text(entry.displayName)
                .font(type.title(20))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            VStack(spacing: 6) {
                Slider(value: $progress, in: 0...max(duration, 0.01)) { editing in
                    if !editing, let player {
                        player.seek(to: CMTime(seconds: progress, preferredTimescale: 600))
                    }
                }
                .tint(theme.accent)
                HStack {
                    Text(timeString(progress))
                    Spacer()
                    Text(timeString(duration))
                }
                .font(type.mono(10.5))
                .foregroundStyle(theme.tertiary)
            }
            .padding(.horizontal, 30)

            Button {
                Haptics.press()
                guard let player else { return }
                if playing {
                    player.pause()
                } else {
                    player.play()
                }
                playing.toggle()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 74, height: 74)
                    .background(Circle().fill(theme.accentGradient))
                    .shadow(color: theme.accent.opacity(0.35), radius: 16, y: 8)
            }
            .buttonStyle(PressableStyle())
            Spacer(minLength: 20)
        }
        .onAppear(perform: start)
        .onDisappear {
            player?.pause()
            if let observer { player?.removeTimeObserver(observer) }
            observer = nil
        }
    }

    private func start() {
        guard player == nil else { return }
        let player = AVPlayer(url: entry.url)
        self.player = player
        if let item = player.currentItem {
            Task {
                let assetDuration = try? await item.asset.load(.duration)
                if let assetDuration { duration = CMTimeGetSeconds(assetDuration) }
            }
        }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                  queue: .main) { time in
            progress = CMTimeGetSeconds(time)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Shortcuts and other files

struct ShortcutReader: View {
    let entry: Entry
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var model: CometModel

    private var address: String? {
        guard let text = try? String(contentsOf: entry.url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("[internetShortcut]") {
            for line in trimmed.components(separatedBy: .newlines) where line.lowercased().hasPrefix("url=") {
                return String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            }
        }
        return trimmed.hasPrefix("http") ? trimmed : nil
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Glyph(symbol: "link", size: 74)
            Text(entry.displayName)
                .font(type.title(22))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
            if let address, let url = URL(string: address) {
                Text(address)
                    .font(type.mono(11.5))
                    .foregroundStyle(theme.tertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                PrimaryAction(title: "Open link", icon: "arrow.up.right") {
                    openURL(url)
                }
                Button {
                    UIPasteboard.general.string = address
                    model.toast.show("Copied", tone: .success)
                } label: {
                    Text("Copy address")
                        .font(type.label(14, weight: .semibold))
                        .foregroundStyle(theme.secondary)
                }
            } else {
                Text("This shortcut doesn't contain a link.")
                    .font(type.prose(13))
                    .foregroundStyle(theme.tertiary)
            }
            Spacer()
        }
    }
}

struct GenericFile: View {
    let entry: Entry
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Glyph(symbol: entry.kind.symbol, size: 74)
            Text(entry.displayName)
                .font(type.title(20))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Text("\(entry.kind.displayLabel) · \(ByteCount.format(entry.size))")
                .font(type.mono(11.5))
                .foregroundStyle(theme.tertiary)
            ShareLink(item: entry.url) {
                Label("Share or open elsewhere", systemImage: "square.and.arrow.up")
                    .font(type.label(14, weight: .semibold))
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(Capsule().fill(theme.accentGradient))
            }
            Spacer()
        }
    }
}
