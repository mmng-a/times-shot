import AppKit
import SwiftUI
import TimesShotCore
import UniformTypeIdentifiers

struct DraftEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var richText: AttributedString?
    let send: () -> Void
    let discard: () -> Void
    let addFiles: ([URL]) -> Void
    let addImage: (Data, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = PostingTextView(usingTextLayoutManager: true)
        // Drafts include list markers, so TextKit must not generate them again.
        editor.textContentStorage?.includesTextListMarkers = true
        editor.delegate = context.coordinator
        editor.isRichText = true
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.usesFontPanel = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.font = RichText.font
        editor.textColor = .textColor
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 4, height: 10)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.registerForDraggedTypes([.fileURL] + PostingTextView.imagePasteboardTypes.map(\.type))
        editor.textStorage?.setAttributedString(NSAttributedString(richText ?? RichText.fromMarkdown(text)))
        editor.textStorage?.delegate = context.coordinator
        editor.typingAttributes = [.font: RichText.font, .foregroundColor: NSColor.textColor]
        editor.send = send
        editor.discard = discard
        editor.addFiles = addFiles
        editor.addImage = addImage
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? PostingTextView else { return }
        let coordinator = context.coordinator
        if (coordinator.text != text || coordinator.richText != richText), !editor.hasMarkedText() {
            coordinator.updating = true
            editor.textStorage?.setAttributedString(NSAttributedString(richText ?? RichText.fromMarkdown(text)))
            editor.typingAttributes = [.font: RichText.font, .foregroundColor: NSColor.textColor]
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            editor.undoManager?.removeAllActions()
            coordinator.text = text
            coordinator.richText = richText
            coordinator.updating = false
        }
        editor.send = send
        editor.discard = discard
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate, @MainActor NSTextStorageDelegate {
        var parent: DraftEditor
        var text: String
        var richText: AttributedString?
        var updating = false
        init(_ parent: DraftEditor) {
            self.parent = parent
            text = parent.text
            richText = parent.richText
        }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            sync(editor.attributedString())
        }
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            sync(textStorage)
        }
        private func sync(_ content: NSAttributedString) {
            guard !updating else { return }
            let newText = content.string
            let newRichText = AttributedString(content)
            guard text != newText || richText != newRichText else { return }
            text = newText
            richText = newRichText
            parent.text = text
            parent.richText = richText
        }
    }
}

final class PostingTextView: NSTextView {
    static let imagePasteboardTypes: [(type: NSPasteboard.PasteboardType, filename: String)] = [
        (NSPasteboard.PasteboardType(UTType.gif.identifier), "clipboard.gif"),
        (NSPasteboard.PasteboardType(UTType.webP.identifier), "clipboard.webp"),
        (.png, "clipboard.png"),
        (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "clipboard.jpg"),
        (.tiff, "clipboard.tiff")
    ]

    var send: (() -> Void)?
    var discard: (() -> Void)?
    var addFiles: (([URL]) -> Void)?
    var addImage: ((Data, String) -> Void)?

    override func didChangeText() {
        super.didChangeText()
        if string.isEmpty, !hasMarkedText() {
            typingAttributes = [.font: RichText.font, .foregroundColor: NSColor.textColor,
                                .paragraphStyle: NSParagraphStyle.default]
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        if insertString is String, !hasMarkedText(), selectedRange().length == 0 {
            applyInputFormatting()
        }
    }

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), selectedRange().length == 0, let (range, style) = currentListItem() else {
            super.insertNewline(sender)
            return
        }
        let content = (string as NSString).substring(with: range).dropFirst(2)
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            leaveList(range: range)
        } else {
            let attributes: [NSAttributedString.Key: Any] = [.font: RichText.font, .foregroundColor: NSColor.textColor, .paragraphStyle: style]
            super.insertText(NSAttributedString(string: "\n•\t", attributes: attributes), replacementRange: selectedRange())
            typingAttributes = attributes
        }
    }

    override func deleteBackward(_ sender: Any?) {
        if !hasMarkedText(), selectedRange().length == 0, let (range, _) = currentListItem(), selectedRange().location == range.location + 2 {
            leaveList(range: range)
        } else { super.deleteBackward(sender) }
    }

    private func currentListItem() -> (NSRange, NSParagraphStyle)? {
        let source = string as NSString
        let range = source.paragraphRange(for: selectedRange())
        guard range.length >= 2, source.substring(with: range).hasPrefix("•\t"),
              let style = textStorage?.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
              !style.textLists.isEmpty else { return nil }
        return (range, style)
    }

    private func leaveList(range: NSRange) {
        let content = NSMutableAttributedString(attributedString: attributedString().attributedSubstring(from: range))
        content.deleteCharacters(in: NSRange(location: 0, length: 2))
        content.addAttribute(.paragraphStyle, value: NSParagraphStyle.default, range: NSRange(location: 0, length: content.length))
        let caret = max(range.location, selectedRange().location - 2)
        breakUndoCoalescing()
        super.insertText(content, replacementRange: range)
        setSelectedRange(NSRange(location: caret, length: 0))
        typingAttributes[.paragraphStyle] = NSParagraphStyle.default
        breakUndoCoalescing()
    }

    private func applyInputFormatting() {
        let caret = selectedRange().location
        let source = string as NSString
        guard caret > 0, !(typingAttributes[.font] as? NSFont ?? RichText.font).isFixedPitch else { return }
        let paragraph = source.paragraphRange(for: NSRange(location: caret, length: 0))
        let prefix = source.substring(with: NSRange(location: paragraph.location, length: caret - paragraph.location))
        if prefix.hasPrefix("- ") || prefix.hasPrefix("* ") {
            let content = NSMutableAttributedString(attributedString: attributedString().attributedSubstring(from: paragraph))
            content.replaceCharacters(in: NSRange(location: 0, length: 2), with: "•\t")
            let style = NSMutableParagraphStyle()
            style.textLists = [NSTextList(markerFormat: .disc, options: 0)]
            style.headIndent = 20
            style.tabStops = [NSTextTab(textAlignment: .left, location: 20)]
            content.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: content.length))
            replaceInput(content, range: paragraph, caret: caret)
            typingAttributes[.paragraphStyle] = style
            return
        }
        let rules: [(String, NSFontTraitMask?, Bool, Bool)] = [
            (#"(?<![\\`])`([^`\n]+)`$"#, nil, false, true),
            (#"(?<![\\*])\*\*([^*\n]+)\*\*$"#, .boldFontMask, false, false),
            (#"(?<![\\*])\*([^*\n]+)\*$"#, .boldFontMask, false, false),
            (#"(?<![\\_])_([^_\n]+)_$"#, .italicFontMask, false, false),
            (#"(?<![\\~])~~([^~\n]+)~~$"#, nil, true, false),
            (#"(?<![\\~])~([^~\n]+)~$"#, nil, true, false)
        ]
        for (pattern, trait, strike, code) in rules {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length)) else { continue }
            let before = (prefix as NSString).substring(to: match.range.location)
            guard before.filter({ $0 == "`" }).count.isMultiple(of: 2) else { continue }
            let bodyRange = match.range(at: 1)
            let body = (prefix as NSString).substring(with: bodyRange)
            guard code || (body.first?.isWhitespace == false && body.last?.isWhitespace == false) else { continue }
            let range = NSRange(location: paragraph.location + bodyRange.location, length: bodyRange.length)
            let content = NSMutableAttributedString(attributedString: attributedString().attributedSubstring(from: range))
            content.enumerateAttributes(in: NSRange(location: 0, length: content.length)) { attributes, range, _ in
                let font = attributes[.font] as? NSFont ?? RichText.font
                if let trait { content.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: range) }
                if strike { content.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
                if code { content.addAttribute(.font, value: RichText.codeFont, range: range) }
            }
            let replacement = NSRange(location: paragraph.location + match.range.location, length: match.range.length)
            replaceInput(content, range: replacement, caret: replacement.location + content.length)
            return
        }
    }

    private func replaceInput(_ content: NSAttributedString, range: NSRange, caret: Int) {
        let attributes = typingAttributes
        breakUndoCoalescing()
        super.insertText(content, replacementRange: range)
        setSelectedRange(NSRange(location: caret, length: 0))
        typingAttributes = attributes
        breakUndoCoalescing()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 36, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            if hasMarkedText() { return super.performKeyEquivalent(with: event) }
            send?()
            return true
        }
        if !hasMarkedText() {
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            switch (modifiers, event.charactersIgnoringModifiers?.lowercased()) {
            case (.command, "b"): formatBold(nil); return true
            case (.command, "i"): formatItalic(nil); return true
            case ([.command, .shift], "x"): formatStrikethrough(nil); return true
            case ([.command, .shift], "c"): formatCode(nil); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let formatting = NSMenu(title: "書式")
        for (title, action, key, modifiers) in [
            ("太字", #selector(formatBold(_:)), "b", NSEvent.ModifierFlags.command),
            ("斜体", #selector(formatItalic(_:)), "i", .command),
            ("取り消し線", #selector(formatStrikethrough(_:)), "x", [.command, .shift]),
            ("コード", #selector(formatCode(_:)), "c", [.command, .shift])
        ] {
            let item = formatting.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = self
        }
        menu.addItem(.separator())
        let item = menu.addItem(withTitle: "書式", action: nil, keyEquivalent: "")
        item.submenu = formatting
        return menu
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if [#selector(formatBold(_:)), #selector(formatItalic(_:)), #selector(formatStrikethrough(_:)), #selector(formatCode(_:))].contains(item.action) {
            return isEditable && !hasMarkedText()
        }
        return super.validateUserInterfaceItem(item)
    }

    @objc func formatBold(_ sender: Any?) { toggleFontTrait(.boldFontMask) }
    @objc func formatItalic(_ sender: Any?) { toggleFontTrait(.italicFontMask) }
    @objc func formatStrikethrough(_ sender: Any?) {
        formatSelection(isEnabled: { ($0[.strikethroughStyle] as? Int ?? 0) != 0 }) { attributes, enabled in
            attributes[.strikethroughStyle] = enabled ? NSUnderlineStyle.single.rawValue : nil
        }
    }
    @objc func formatCode(_ sender: Any?) {
        formatSelection(isEnabled: { ($0[.font] as? NSFont)?.isFixedPitch == true }) { attributes, enabled in
            attributes[.font] = enabled ? RichText.codeFont : RichText.font
            attributes[.presentationIntentAttributeName] = nil
        }
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        let manager = NSFontManager.shared
        formatSelection(isEnabled: { manager.traits(of: $0[.font] as? NSFont ?? RichText.font).contains(trait) }) { attributes, enabled in
            let font = attributes[.font] as? NSFont ?? RichText.font
            attributes[.font] = enabled ? manager.convert(font, toHaveTrait: trait) : manager.convert(font, toNotHaveTrait: trait)
        }
    }

    private func formatSelection(isEnabled: ([NSAttributedString.Key: Any]) -> Bool,
                                 update: (inout [NSAttributedString.Key: Any], Bool) -> Void) {
        guard !hasMarkedText() else { return }
        let range = selectedRange()
        guard range.length > 0 else {
            var attributes = typingAttributes
            update(&attributes, !isEnabled(attributes))
            typingAttributes = attributes
            return
        }
        let selection = NSMutableAttributedString(attributedString: attributedString().attributedSubstring(from: range))
        let entireRange = NSRange(location: 0, length: selection.length)
        var enabled = true
        selection.enumerateAttributes(in: entireRange) { attributes, _, _ in
            if !isEnabled(attributes) { enabled = false }
        }
        let turnOn = !enabled
        selection.enumerateAttributes(in: entireRange) { attributes, range, _ in
            var changed = attributes
            update(&changed, turnOn)
            selection.setAttributes(changed, range: range)
        }
        breakUndoCoalescing()
        insertText(selection, replacementRange: range)
        breakUndoCoalescing()
        setSelectedRange(range)
    }

    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() {
            unmarkText()
            inputContext?.discardMarkedText()
        } else { discard?() }
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.fileURL] + Self.imagePasteboardTypes.map(\.type) + super.readablePasteboardTypes
    }

    override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == .fileURL || Self.imagePasteboardTypes.contains(where: { $0.type == type }) {
            return acceptImages(from: pasteboard)
        }
        return super.readSelection(from: pasteboard, type: type)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        canAcceptImages(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        acceptImages(from: sender.draggingPasteboard)
    }

    private func canAcceptImages(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pasteboard.availableType(from: Self.imagePasteboardTypes.map(\.type)) != nil
    }

    private func acceptImages(from pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            addFiles?(urls)
            return true
        }
        for (type, filename) in Self.imagePasteboardTypes {
            if let data = pasteboard.data(forType: type) {
                addImage?(data, filename)
                return true
            }
        }
        return false
    }
}
