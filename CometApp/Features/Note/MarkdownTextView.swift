//
//  MarkdownTextView.swift
//  Comet
//
//  The writing half of the note screen. A UITextView rather than SwiftUI's
//  TextEditor only because formatting needs to know where the cursor is: bold,
//  a heading, a task line and a link are all edits around a selection.
//

import SwiftUI
import UIKit

@MainActor
final class EditorBridge: ObservableObject {
    weak var textView: UITextView?

    func wrap(_ marker: String, suffix: String? = nil) {
        guard let textView else { return }
        let closing = suffix ?? marker
        let range = textView.selectedRange
        let text = textView.text as NSString
        let selected = text.substring(with: range)
        let replacement: String
        if selected.isEmpty {
            replacement = marker + closing
        } else if selected.hasPrefix(marker) && selected.hasSuffix(closing) && selected.count >= marker.count + closing.count {
            replacement = String(selected.dropFirst(marker.count).dropLast(closing.count))
        } else {
            replacement = marker + selected + closing
        }
        textView.replace(range: range, with: replacement)
        if selected.isEmpty {
            textView.selectedRange = NSRange(location: range.location + marker.count, length: 0)
        }
        Haptics.tap()
    }

    func insert(_ text: String) {
        guard let textView else { return }
        let range = textView.selectedRange
        textView.replace(range: range, with: text)
        textView.selectedRange = NSRange(location: range.location + (text as NSString).length, length: 0)
        Haptics.tap()
    }

    /// Add, or remove, a prefix on each line of the selection.
    func toggleLinePrefix(_ prefix: String) {
        guard let textView else { return }
        let text = textView.text as NSString
        let selection = textView.selectedRange
        let lineRange = text.lineRange(for: selection)
        let block = text.substring(with: lineRange)
        var lines = block.components(separatedBy: "\n")
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allPrefixed = !nonEmpty.isEmpty && nonEmpty.allSatisfy { $0.hasPrefix(prefix) }

        lines = lines.map { line in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            if allPrefixed {
                return String(line.dropFirst(prefix.count))
            }
            // Replace an existing marker of the same family.
            if prefix == "- [ ] " {
                if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") { return "- [ ] " + line.dropFirst(6) }
                if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") { return "- [ ] " + line.dropFirst(2) }
            }
            if prefix.hasPrefix("#") {
                var trimmed = line
                while trimmed.hasPrefix("#") { trimmed.removeFirst() }
                if trimmed.hasPrefix(" ") { trimmed.removeFirst() }
                return prefix + trimmed
            }
            if prefix == "- " && (line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ")) {
                return "- " + line.dropFirst(6)
            }
            return prefix + line
        }
        let replacement = lines.joined(separator: "\n")
        textView.replace(range: lineRange, with: replacement)
        Haptics.tap()
    }

    func focus() {
        textView?.becomeFirstResponder()
    }
}

private extension UITextView {
    func replace(range: NSRange, with text: String) {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let textRange = textRange(from: start, to: end) else { return }
        self.replace(textRange, withText: text)
    }
}

struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var spellcheck: Bool
    var theme: CometTheme
    var bridge: EditorBridge

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = UIColor(theme.ink)
        view.tintColor = UIColor(theme.accent)
        view.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 40, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.alwaysBounceVertical = false
        view.spellCheckingType = spellcheck ? .yes : .no
        view.autocorrectionType = spellcheck ? .yes : .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.keyboardDismissMode = .interactive
        view.text = text
        bridge.textView = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
        view.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.textColor = UIColor(theme.ink)
        view.tintColor = UIColor(theme.accent)
        view.spellCheckingType = spellcheck ? .yes : .no
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownTextView

        init(parent: MarkdownTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}
