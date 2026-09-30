import AppKit
import SwiftUI

/// 行間を広めにとった編集欄。TextEditor では選択範囲の強調ができないので NSTextView を包む。
struct TextArea: NSViewRepresentable {
    @Binding var text: String
    var placeholder = ""
    var highlight: HighlightRequest?
    /// Esc で呼ぶ。true を返したら既定の動作（入力補完）をしない。
    var onEscape: (() -> Bool)?

    static let font = NSFont.systemFont(ofSize: 15)
    static let attributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.4
        paragraph.paragraphSpacing = 4
        return [.font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.textColor]
    }()

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = EscapableTextView(usingTextLayoutManager: false)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.drawsBackground = false
        textView.font = Self.font
        textView.defaultParagraphStyle = Self.attributes[.paragraphStyle] as? NSParagraphStyle
        textView.typingAttributes = Self.attributes
        textView.delegate = context.coordinator
        textView.placeholder = placeholder
        Self.setText(text, in: textView)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? EscapableTextView else { return }
        textView.onEscape = onEscape
        textView.placeholder = placeholder
        if textView.string != text, !textView.hasMarkedText() {
            Self.setText(text, in: textView)
        }
        if let highlight, highlight.id != context.coordinator.lastHighlightID {
            context.coordinator.lastHighlightID = highlight.id
            Self.show(highlight.text, in: textView)
        }
    }

    private static func setText(_ text: String, in textView: NSTextView) {
        textView.string = text
        textView.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: (text as NSString).length))
        clearHighlight(in: textView)
        textView.needsDisplay = true
    }

    /// 修正版の中から該当部分を探して強調する。見つからなければ何もしない。
    private static func show(_ target: String, in textView: NSTextView) {
        let needle = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return }
        let haystack = textView.string as NSString
        var range = haystack.range(of: needle)
        if range.location == NSNotFound,
           let firstLine = needle.components(separatedBy: .newlines).first(where: { !$0.isEmpty }), firstLine != needle {
            range = haystack.range(of: firstLine)
        }
        guard range.location != NSNotFound else { return }
        clearHighlight(in: textView)
        textView.layoutManager?.addTemporaryAttribute(
            .backgroundColor, value: highlightColor, forCharacterRange: range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    /// ライトでは明るい黄色、ダークでは濁らないよう薄い青に。
    private static let highlightColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.systemBlue.withAlphaComponent(0.35)
            : NSColor.systemYellow.withAlphaComponent(0.40)
    }

    fileprivate static func clearHighlight(in textView: NSTextView) {
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextArea
        var lastHighlightID: UUID?

        init(_ parent: TextArea) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            TextArea.clearHighlight(in: textView)
            parent.text = textView.string
        }
    }
}

final class EscapableTextView: NSTextView {
    var onEscape: (() -> Bool)?
    var placeholder = "" {
        didSet {
            setAccessibilityPlaceholderValue(placeholder)
            needsDisplay = true
        }
    }

    // SwiftUI の Binding は未確定文字をまだ受け取っていないことがある。
    // 案内文は NSTextView 自身の内容と変換状態から表示を決める。
    var showsPlaceholder: Bool {
        !placeholder.isEmpty && string.isEmpty && !hasMarkedText()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsPlaceholder else { return }
        let origin = textContainerOrigin
        let padding = textContainer?.lineFragmentPadding ?? 0
        let rect = NSRect(x: origin.x + padding, y: origin.y,
                          width: max(0, bounds.width - 2 * (origin.x + padding)),
                          height: max(0, bounds.height - origin.y))
        var attributes = TextArea.attributes
        attributes[.foregroundColor] = NSColor.secondaryLabelColor
        (placeholder as NSString).draw(in: rect, withAttributes: attributes)
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        needsDisplay = true
    }

    override func unmarkText() {
        super.unmarkText()
        needsDisplay = true
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func cancelOperation(_ sender: Any?) {
        if onEscape?() == true { return }
        super.cancelOperation(sender)
    }
}
