//
//  MarkdownView.swift
//  Comet
//
//  Markdown drawn as SwiftUI rather than HTML: headings keep the app's rounded
//  display face, tasks have real checkboxes, code keeps its indentation, and a
//  link is a link. The reader cannot execute anything a note contains.
//

import SwiftUI

struct MarkdownView: View {
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    let text: String
    var bodySize: CGFloat = 16.5
    var onToggleTask: ((String, Bool) -> Void)? = nil
    var imageURL: ((String) -> URL?)? = nil

    private var blocks: [Block] { Markdown.blocks(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let inlines):
            heading(level: level, inlines: inlines)
        case .paragraph(let inlines):
            paragraph(inlines, size: bodySize)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    if item.box {
                        Button {
                            Haptics.tap()
                            onToggleTask?(Markdown.plainText(item.inlines), item.done)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Image(systemName: item.done ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(item.done ? theme.accent : theme.tertiary)
                                paragraph(item.inlines, size: bodySize)
                                    .strikethrough(item.done, color: theme.tertiary)
                                    .opacity(item.done ? 0.65 : 1)
                            }
                        }
                        .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
                        .disabled(onToggleTask == nil)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Circle()
                                .fill(theme.accent)
                                .frame(width: 5, height: 5)
                                .offset(y: -5)
                            paragraph(item.inlines, size: bodySize)
                        }
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("\(item.number ?? index + 1).")
                            .font(type.mono(bodySize - 1, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(minWidth: 20, alignment: .trailing)
                        paragraph(item.inlines, size: bodySize)
                    }
                }
            }
        case .quote(let inlines):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.accent.opacity(0.55))
                    .frame(width: 3)
                paragraph(inlines, size: bodySize)
                    .italic()
                    .foregroundStyle(theme.secondary)
            }
            .padding(.vertical, 2)
        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 6) {
                if !language.isEmpty {
                    Text(language.uppercased())
                        .font(type.label(9.5, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(theme.tertiary)
                }
                ScrollView(.horizontal) {
                    Text(code)
                        .font(type.mono(bodySize - 2))
                        .foregroundStyle(theme.ink)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .scrollIndicators(.hidden)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.raised))
            }
        case .rule:
            Rectangle()
                .fill(theme.hairline)
                .frame(height: 1)
                .padding(.vertical, 6)
        case .image(let alt, let src):
            image(alt: alt, src: src)
        case .table(let header, let rows):
            table(header: header, rows: rows)
        }
    }

    private func heading(level: Int, inlines: [Inline]) -> some View {
        Text(attributed(inlines, size: headingSize(level), weight: .bold))
            .font(type.display(headingSize(level)))
            .foregroundStyle(theme.ink)
            .padding(.top, level == 1 ? 6 : 10)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 27
        case 2: return 22
        case 3: return 19
        default: return 17
        }
    }

    private func paragraph(_ inlines: [Inline], size: CGFloat) -> Text {
        Text(attributed(inlines, size: size, weight: .regular))
            .font(type.prose(size))
            .foregroundStyle(theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(4)
    }

    private func attributed(_ inlines: [Inline], size: CGFloat, weight: Font.Weight) -> AttributedString {
        var output = AttributedString()
        for inline in inlines {
            var piece: AttributedString
            switch inline {
            case .text(let value):
                piece = AttributedString(value)
                piece.font = .system(size: size, weight: weight)
                piece.foregroundColor = theme.ink
            case .strong(let value):
                piece = AttributedString(value)
                piece.font = .system(size: size, weight: .bold)
                piece.foregroundColor = theme.ink
            case .emphasis(let value):
                piece = AttributedString(value)
                piece.font = .system(size: size, weight: weight).italic()
                piece.foregroundColor = theme.ink
            case .strike(let value):
                piece = AttributedString(value)
                piece.font = .system(size: size, weight: weight)
                piece.foregroundColor = theme.secondary
                piece.strikethroughStyle = .single
            case .code(let value):
                piece = AttributedString(value)
                piece.font = .system(size: size - 1.5, design: .monospaced)
                piece.foregroundColor = theme.accent
                piece.backgroundColor = theme.accent.opacity(0.10)
            case .link(let label, let href):
                piece = AttributedString(label)
                piece.font = .system(size: size, weight: weight)
                piece.foregroundColor = theme.accent
                piece.underlineStyle = .single
                if let url = URL(string: href) { piece.link = url }
            case .image(let alt, _):
                piece = AttributedString("📷 " + (alt.isEmpty ? "image" : alt))
                piece.font = .system(size: size - 1)
                piece.foregroundColor = theme.tertiary
            case .br:
                piece = AttributedString("\n")
            }
            output.append(piece)
        }
        return output
    }

    private func image(alt: String, src: String) -> some View {
        Group {
            if let url = imageURL?(src) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    case .failure:
                        unavailableImage(alt)
                    case .empty:
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(theme.raised)
                            .frame(height: 140)
                            .overlay(ProgressView().tint(theme.accent))
                    @unknown default:
                        unavailableImage(alt)
                    }
                }
            } else {
                unavailableImage(alt)
            }
            if !alt.isEmpty {
                Text(alt)
                    .font(type.prose(11.5))
                    .foregroundStyle(theme.tertiary)
            }
        }
    }

    private func unavailableImage(_ alt: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(theme.tertiary)
            Text(alt.isEmpty ? "Image not found" : alt)
                .font(type.prose(12))
                .foregroundStyle(theme.tertiary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.raised))
    }

    private func table(header: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            tableRow(header, isHeader: true)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                CometDivider()
                tableRow(row, isHeader: false)
                if index == rows.count - 1 { EmptyView() }
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.raised.opacity(0.6)))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func tableRow(_ cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(attributed(Markdown.inline(cell), size: 12.5, weight: isHeader ? .bold : .regular))
                    .font(type.prose(12.5, weight: isHeader ? .semibold : .regular))
                    .foregroundStyle(isHeader ? theme.secondary : theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
