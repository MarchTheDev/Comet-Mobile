//
//  WhiteboardScreen.swift
//  Comet
//
//  A whiteboard you can actually use with a thumb. Two modes: move things
//  around, or draw. Cards can be text, a to-do list, a shape or a link, they
//  connect with a line, and the whole thing saves into the `.comet-whiteboard`
//  format the desktop app reads.
//

import SwiftUI
import UIKit

struct WhiteboardScreen: View {
    let entry: Entry
    let close: () -> Void

    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    private enum Mode { case move, draw }

    @State private var board = WhiteboardDocument()
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var mode: Mode = .move
    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var panStart: CGSize = .zero
    @State private var pinching: CGFloat = 1
    @State private var stroke: WhiteboardStroke?
    @State private var ink = BoardColor.palette[0]
    @State private var editing: WhiteboardItem?
    @State private var confirmingDelete = false

    var body: some View {
        ZStack(alignment: .top) {
            background

            GeometryReader { geometry in
                let size = geometry.size
                ZStack(alignment: .topLeading) {
                    Color.clear.contentShape(Rectangle())

                    connectionsLayer

                    strokesLayer

                    ForEach($board.items) { $item in
                        WhiteboardCardView(item: $item, selected: editing?.id == item.id) {
                            editing = item
                        }
                        .position(x: item.x + item.width / 2, y: item.y + item.height / 2)
                    }

                    if let stroke {
                        Path { path in
                            guard let first = stroke.points.first else { return }
                            path.move(to: CGPoint(x: first.x, y: first.y))
                            for point in stroke.points.dropFirst() {
                                path.addLine(to: CGPoint(x: point.x, y: point.y))
                            }
                        }
                        .stroke(Color(hex: stroke.color), style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .scaleEffect(scale, anchor: .topLeading)
                .offset(offset)
                .gesture(canvasGesture)
                .simultaneousGesture(magnification)
            }
            .clipped()

            topChrome
            bottomBar
        }
        .task { load() }
        .onChange(of: board) { _, value in scheduleSave(value) }
        .onDisappear {
            saveTask?.cancel()
            model.saveText(board.serialized(), at: entry)
        }
        .sheet(item: $editing) { item in
            WhiteboardItemSheet(board: $board, item: item)
                .environmentObject(model)
                .environment(\.comet, theme)
                .environment(\.type, type)
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
                .presentationCornerRadius(34)
        }
        .confirmationDialog("Delete this whiteboard?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.delete(entry)
                close()
            }
            Button("Keep", role: .cancel) {}
        }
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            theme.canvasGradient
            DotGrid(spacing: 28 * scale, color: theme.tertiary.opacity(0.18), offset: offset)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    // MARK: Layers

    private var connectionsLayer: some View {
        Canvas { context, _ in
            for connection in board.connections {
                guard let from = board.items.first(where: { $0.id == connection.from }),
                      let to = board.items.first(where: { $0.id == connection.to }) else { continue }
                var path = Path()
                let start = CGPoint(x: from.x + from.width / 2, y: from.y + from.height / 2)
                let end = CGPoint(x: to.x + to.width / 2, y: to.y + to.height / 2)
                path.move(to: start)
                let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 40)
                path.addQuadCurve(to: end, control: mid)
                context.stroke(path, with: .color(Color(hex: connection.color).opacity(0.65)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    private var strokesLayer: some View {
        Canvas { context, _ in
            for stroke in board.strokes {
                guard let first = stroke.points.first else { continue }
                var path = Path()
                path.move(to: CGPoint(x: first.x, y: first.y))
                for point in stroke.points.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x, y: point.y))
                }
                context.stroke(path, with: .color(Color(hex: stroke.color)),
                               style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Gestures

    private var canvasGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if mode == .draw {
                    if stroke == nil {
                        stroke = WhiteboardStroke(color: ink, width: 3, points: [])
                    }
                    let point = WhiteboardStroke.Point(
                        x: Double((value.location.x - offset.width) / scale),
                        y: Double((value.location.y - offset.height) / scale)
                    )
                    stroke?.points.append(point)
                } else if mode == .move {
                    offset = CGSize(width: panStart.width + value.translation.width,
                                    height: panStart.height + value.translation.height)
                }
            }
            .onEnded { _ in
                if mode == .draw, let finished = stroke {
                    board.strokes.append(finished)
                    stroke = nil
                    Haptics.tap()
                } else {
                    panStart = offset
                }
            }
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(2.4, max(0.35, pinching * value))
            }
            .onEnded { _ in
                pinching = scale
            }
    }

    // MARK: Chrome

    private var topChrome: some View {
        HStack(spacing: 8) {
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
            .accessibilityLabel("Close whiteboard")

            Spacer()

            HStack(spacing: 3) {
                modeButton(symbol: "hand.draw", target: .move, label: "Move")
                modeButton(symbol: "pencil.tip", target: .draw, label: "Draw")
            }
            .padding(4)
            .glassPanel(radius: 24)

            Menu {
                Button {
                    addItem(.text)
                } label: {
                    Label("Text card", systemImage: "text.alignleft")
                }
                Button {
                    addItem(.todo)
                } label: {
                    Label("To-do card", systemImage: "checklist")
                }
                Button {
                    addItem(.shape)
                } label: {
                    Label("Shape", systemImage: "square.on.circle")
                }
                Button {
                    addItem(.link)
                } label: {
                    Label("Link card", systemImage: "link")
                }
                Divider()
                Button {
                    offset = .zero
                    scale = 1
                    pinching = 1
                } label: {
                    Label("Reset view", systemImage: "arrow.counterclockwise")
                }
                if !board.strokes.isEmpty || !board.items.isEmpty {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete board", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(theme.accentGradient))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func modeButton(symbol: String, target: Mode, label: String) -> some View {
        Button {
            guard mode != target else { return }
            Haptics.select()
            withAnimation(Motion.snappy) { mode = target }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(mode == target ? theme.onAccent : theme.secondary)
                .frame(width: 40, height: 34)
                .background {
                    if mode == target { Capsule().fill(theme.accentGradient) }
                }
        }
        .buttonStyle(PressableStyle(scale: 0.94, haptic: nil))
        .accessibilityLabel(label)
    }

    private var bottomBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                if mode == .draw {
                    ScrollView(.horizontal) {
                        HStack(spacing: 7) {
                            ForEach(BoardColor.palette, id: \.self) { hex in
                                Button {
                                    Haptics.select()
                                    ink = hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 24, height: 24)
                                        .overlay(Circle().strokeBorder(theme.ink.opacity(ink == hex ? 0.7 : 0), lineWidth: 2))
                                }
                                .buttonStyle(PressableStyle(scale: 0.9, haptic: nil))
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: 220)
                    if !board.strokes.isEmpty {
                        Button {
                            board.strokes.removeLast()
                            Haptics.tap()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.ink)
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(PressableStyle())
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw")
                        Text("Drag to pan · pinch to zoom")
                    }
                    .font(type.mono(10.5))
                    .foregroundStyle(theme.tertiary)
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .glassPanel(radius: 26)
            .padding(.bottom, 10)
        }
        .allowsHitTesting(true)
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        board = WhiteboardDocument.parse(model.readText(entry)) ?? WhiteboardDocument()
        loaded = true
    }

    private func scheduleSave(_ value: WhiteboardDocument) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            model.saveText(value.serialized(), at: entry)
        }
    }

    private func addItem(_ type: WhiteboardItemType) {
        let center = CGPoint(x: (UIScreen.main.bounds.width / 2 - offset.width) / scale,
                             y: (UIScreen.main.bounds.height / 2 - offset.height) / scale)
        var item = WhiteboardItem(type: type,
                                  x: Double(center.x - 120),
                                  y: Double(center.y - 70),
                                  text: type == .text ? "New card" : "",
                                  color: ink,
                                  width: type == .shape ? 160 : 240,
                                  height: type == .shape ? 160 : 140)
        if type == .todo {
            item.title = "Checklist"
            item.todos = [WhiteboardTodoEntry(text: "First thing")]
        }
        if type == .link {
            item.links = [WhiteboardLinkEntry(url: "https://")]
            item.text = "Link"
        }
        board.items.append(item)
        editing = item
        Haptics.success()
    }
}

// MARK: - Card

struct WhiteboardCardView: View {
    @Binding var item: WhiteboardItem
    var selected: Bool
    var onEdit: () -> Void

    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @State private var dragOrigin: CGPoint?

    var body: some View {
        content
            .frame(width: item.width, height: item.height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: item.color).opacity(item.filled ? 0.85 : 0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(hex: item.color).opacity(selected ? 0.9 : 0.55),
                                  lineWidth: selected ? 2 : 1.2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if dragOrigin == nil { dragOrigin = CGPoint(x: item.x, y: item.y) }
                        guard let origin = dragOrigin else { return }
                        item.x = origin.x + value.translation.width
                        item.y = origin.y + value.translation.height
                    }
                    .onEnded { _ in dragOrigin = nil }
            )
            .onTapGesture(perform: onEdit)
            .contextMenu {
                Button(role: .destructive) {
                    item.text = ""
                } label: {
                    Label("Clear text", systemImage: "eraser")
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !item.title.isEmpty {
                Text(item.title)
                    .font(type.label(11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color(hex: item.color))
                    .lineLimit(1)
            }

            switch item.type {
            case .text:
                Text(item.text.isEmpty ? "Empty card" : item.text)
                    .font(type.prose(14, weight: .medium))
                    .foregroundStyle(theme.ink)
                    .lineLimit(6)
            case .todo:
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.todos.prefix(5)) { entry in
                        HStack(spacing: 6) {
                            Image(systemName: entry.done ? "checkmark.square.fill" : "square")
                                .font(.system(size: 11))
                                .foregroundStyle(entry.done ? Color(hex: item.color) : theme.tertiary)
                            Text(entry.text)
                                .font(type.prose(12.5))
                                .foregroundStyle(entry.done ? theme.tertiary : theme.ink)
                                .strikethrough(entry.done, color: theme.tertiary)
                                .lineLimit(1)
                        }
                    }
                    if item.todos.isEmpty {
                        Text("Empty list")
                            .font(type.prose(12))
                            .foregroundStyle(theme.tertiary)
                    }
                }
            case .shape:
                ZStack {
                    shape
                        .fill(item.filled ? Color(hex: item.color).opacity(0.8) : Color.clear)
                    shape
                        .stroke(Color(hex: item.color), lineWidth: 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .link:
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 11, weight: .semibold))
                    Text(item.links.first?.url ?? "No link")
                        .font(type.prose(11.5))
                        .lineLimit(2)
                }
                .foregroundStyle(theme.secondary)
            case .image:
                Text(item.text)
                    .font(type.prose(12))
                    .foregroundStyle(theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var shape: AnyShape {
        switch item.shape {
        case .rectangle: return AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .ellipse: return AnyShape(Ellipse())
        case .diamond: return AnyShape(DiamondShape())
        case .triangle: return AnyShape(TriangleShape())
        }
    }
}

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct DotGrid: View {
    let spacing: CGFloat
    let color: Color
    let offset: CGSize

    var body: some View {
        Canvas { context, size in
            guard spacing > 6 else { return }
            var x = offset.width.truncatingRemainder(dividingBy: spacing)
            while x < size.width {
                var y = offset.height.truncatingRemainder(dividingBy: spacing)
                while y < size.height {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)),
                                 with: .color(color))
                    y += spacing
                }
                x += spacing
            }
        }
    }
}

// MARK: - Item sheet

struct WhiteboardItemSheet: View {
    @Binding var board: WhiteboardDocument
    let item: WhiteboardItem

    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var title: String
    @State private var color: String
    @State private var todos: [WhiteboardTodoEntry]
    @State private var link: String
    @State private var shape: WhiteboardShape
    @State private var filled: Bool
    @State private var newTodo = ""

    init(board: Binding<WhiteboardDocument>, item: WhiteboardItem) {
        self._board = board
        self.item = item
        _text = State(initialValue: item.text)
        _title = State(initialValue: item.title)
        _color = State(initialValue: item.color)
        _todos = State(initialValue: item.todos)
        _link = State(initialValue: item.links.first?.url ?? "")
        _shape = State(initialValue: item.shape)
        _filled = State(initialValue: item.filled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetGrabber()
            HStack {
                Text(item.type == .shape ? "Shape" : "Card")
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

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Label", text: $title)
                        .font(type.prose(14))
                        .foregroundStyle(theme.ink)
                        .padding(11)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(theme.raised))

                    if item.type == .text {
                        TextField("Text", text: $text, axis: .vertical)
                            .font(type.prose(15))
                            .foregroundStyle(theme.ink)
                            .lineLimit(2...8)
                            .padding(11)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(theme.raised))
                    }

                    if item.type == .todo {
                        ForEach(Array(todos.enumerated()), id: \.element.id) { index, entry in
                            HStack(spacing: 8) {
                                Button {
                                    todos[index].done.toggle()
                                    Haptics.select()
                                } label: {
                                    Image(systemName: entry.done ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(entry.done ? theme.accent : theme.tertiary)
                                }
                                .buttonStyle(PressableStyle(scale: 0.9, haptic: nil))
                                Text(entry.text)
                                    .font(type.prose(13.5))
                                    .foregroundStyle(entry.done ? theme.tertiary : theme.ink)
                                Spacer()
                                Button {
                                    todos.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(theme.tertiary)
                                }
                                .buttonStyle(PressableStyle(scale: 0.9, haptic: nil))
                            }
                        }
                        HStack(spacing: 8) {
                            TextField("Add an item", text: $newTodo)
                                .font(type.prose(13.5))
                                .foregroundStyle(theme.ink)
                                .padding(.horizontal, 10)
                                .frame(height: 36)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surface))
                                .onSubmit(addTodo)
                            Button(action: addTodo) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(theme.onAccent)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(theme.accent))
                            }
                            .buttonStyle(PressableStyle(scale: 0.9, haptic: nil))
                        }
                    }

                    if item.type == .link {
                        TextField("https://", text: $link)
                            .font(type.mono(13))
                            .foregroundStyle(theme.ink)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(11)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(theme.raised))
                    }

                    if item.type == .shape {
                        HStack(spacing: 8) {
                            ForEach(WhiteboardShape.allCases, id: \.self) { option in
                                Button {
                                    Haptics.select()
                                    shape = option
                                } label: {
                                    Image(systemName: option.symbol)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(shape == option ? theme.onAccent : theme.secondary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 40)
                                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(shape == option ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.surface)))
                                }
                                .buttonStyle(PressableStyle(scale: 0.95, haptic: nil))
                            }
                        }
                        Toggle("Filled", isOn: $filled)
                            .font(type.prose(14))
                            .tint(theme.accent)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("COLOUR")
                            .font(type.label(10, weight: .bold))
                            .tracking(1.3)
                            .foregroundStyle(theme.tertiary)
                        HStack(spacing: 8) {
                            ForEach(BoardColor.palette, id: \.self) { hex in
                                Button {
                                    Haptics.select()
                                    color = hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 28, height: 28)
                                        .overlay(Circle().strokeBorder(theme.ink.opacity(color == hex ? 0.8 : 0), lineWidth: 2))
                                }
                                .buttonStyle(PressableStyle(scale: 0.9, haptic: nil))
                            }
                        }
                    }

                    Button(role: .destructive) {
                        board.items.removeAll { $0.id == item.id }
                        board.connections.removeAll { $0.from == item.id || $0.to == item.id }
                        dismiss()
                    } label: {
                        Label("Delete card", systemImage: "trash")
                            .font(type.label(13.5, weight: .semibold))
                            .foregroundStyle(Color.red.opacity(0.9))
                    }
                    .padding(.top, 4)
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvasGradient.ignoresSafeArea())
    }

    private func addTodo() {
        let value = newTodo.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        todos.append(WhiteboardTodoEntry(text: value))
        newTodo = ""
    }

    private func save() {
        guard let index = board.items.firstIndex(where: { $0.id == item.id }) else { return }
        board.items[index].text = text
        board.items[index].title = title
        board.items[index].color = color
        board.items[index].todos = todos
        board.items[index].shape = shape
        board.items[index].filled = filled
        if !link.isEmpty {
            board.items[index].links = [WhiteboardLinkEntry(id: board.items[index].links.first?.id ?? UUID().uuidString,
                                                            url: link, showEmbed: true)]
        }
    }
}
