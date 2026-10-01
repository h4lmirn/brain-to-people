import AppKit
import SwiftUI

/// 修正版の中で、直した箇所に付ける印。カーソルを重ねると、元の表現と理由が出る。
struct TextMark: Equatable {
    let text: String
    let note: String
}

/// 行間を広めにとった編集欄。TextEditor では選択範囲の強調ができないので NSTextView を包む。
struct TextArea: NSViewRepresentable {
    @Binding var text: String
    var placeholder = ""
    var highlight: HighlightRequest?
    /// 直した箇所に薄い印を付ける。
    var marks: [TextMark] = []
    /// 修正点の行にカーソルがあるとき、該当部分を濃くする。
    var emphasis: String?
    var isEditable = true
    /// 文章が伸びていく間、末尾を見せ続ける。
    var followsEnd = false
    /// 0〜1。背景の画像が透けるときに、文字の周りへ薄い縁取りを足して読みやすくする。
    var haloStrength: Double = 0
    /// Esc で呼ぶ。true を返したら既定の動作（入力補完）をしない。
    var onEscape: (() -> Bool)?

    static let font = NSFont.systemFont(ofSize: 15)
    static let attributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.4
        paragraph.paragraphSpacing = 4
        return [.font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.textColor]
    }()

    private static func halo(_ strength: Double) -> NSShadow? {
        guard strength > 0.05 else { return nil }
        let shadow = NSShadow()
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 4
        shadow.shadowColor = NSColor.windowBackgroundColor.withAlphaComponent(min(0.9, strength * 0.9))
        return shadow
    }

    private static func applyHalo(_ strength: Double, to textView: NSTextView) {
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        let shadow = halo(strength)
        if let shadow {
            textView.textStorage?.addAttribute(.shadow, value: shadow, range: full)
            textView.typingAttributes[.shadow] = shadow
        } else {
            textView.textStorage?.removeAttribute(.shadow, range: full)
            textView.typingAttributes[.shadow] = nil
        }
    }

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
        textView.isEditable = isEditable
        let coordinator = context.coordinator
        var needsMarks = false
        if textView.string != text, !textView.hasMarkedText() {
            Self.setText(text, in: textView)
            Self.applyHalo(haloStrength, to: textView)
            coordinator.lastHalo = haloStrength
            needsMarks = true
            if followsEnd { textView.scrollToEndOfDocument(nil) }
        } else if coordinator.lastHalo != haloStrength {
            Self.applyHalo(haloStrength, to: textView)
            coordinator.lastHalo = haloStrength
        }
        if needsMarks || coordinator.lastMarks != marks || coordinator.lastEmphasis != emphasis {
            coordinator.lastMarks = marks
            coordinator.lastEmphasis = emphasis
            Self.refreshMarks(in: textView, marks: marks, emphasis: emphasis)
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
        textView.layoutManager?.removeTemporaryAttribute(.toolTip, forCharacterRange: full)
    }

    private static let markTint = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 1, green: 0.69, blue: 0.53, alpha: 1)
            : NSColor(red: 0.66, green: 0.26, blue: 0.16, alpha: 1)
    }

    /// 直した箇所の印を付けなおす。文章が変わるたびに、文字列を探しなおして位置を合わせる。
    fileprivate static func refreshMarks(in textView: NSTextView, marks: [TextMark], emphasis: String?) {
        clearHighlight(in: textView)
        guard let layout = textView.layoutManager else { return }
        let haystack = textView.string as NSString
        for mark in marks {
            let needle = mark.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { continue }
            let range = haystack.range(of: needle)
            guard range.location != NSNotFound else { continue }
            layout.addTemporaryAttribute(.backgroundColor, value: markTint.withAlphaComponent(0.10), forCharacterRange: range)
            if !mark.note.isEmpty {
                layout.addTemporaryAttribute(.toolTip, value: mark.note, forCharacterRange: range)
            }
        }
        if let emphasis {
            let needle = emphasis.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = haystack.range(of: needle)
            if !needle.isEmpty, range.location != NSNotFound {
                layout.addTemporaryAttribute(.backgroundColor, value: markTint.withAlphaComponent(0.28), forCharacterRange: range)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextArea
        var lastHighlightID: UUID?
        var lastMarks: [TextMark] = []
        var lastEmphasis: String?
        var lastHalo: Double = 0

        init(_ parent: TextArea) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            TextArea.clearHighlight(in: textView)
            lastMarks = []
            lastEmphasis = nil
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
