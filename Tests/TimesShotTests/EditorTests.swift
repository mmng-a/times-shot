import AppKit
import SwiftUI
import Testing
import TimesShotCore
@testable import TimesShot

@MainActor @Test func escapeDiscardsOnlyAfterIMECompositionEnds() {
    _ = NSApplication.shared
    let editor = PostingTextView(frame: .zero)
    var discarded = 0
    editor.discard = { discarded += 1 }
    editor.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(editor.hasMarkedText())
    editor.cancelOperation(nil)
    #expect(discarded == 0)
    editor.unmarkText()
    editor.cancelOperation(nil)
    #expect(discarded == 1)
}

@MainActor @Test func commandReturnSendsWithoutTreatingIMEConfirmationAsSend() throws {
    _ = NSApplication.shared
    let editor = PostingTextView(frame: .zero)
    var sent = 0
    editor.send = { sent += 1 }
    let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                            timestamp: 0, windowNumber: 0, context: nil,
                                            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
    #expect(editor.performKeyEquivalent(with: event))
    #expect(sent == 1)
    editor.setMarkedText("へんかん", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    _ = editor.performKeyEquivalent(with: event)
    #expect(sent == 1)
}

@MainActor @Test(arguments: [NSBitmapImageRep.FileType.png, .tiff, .jpeg])
func pastedImageBecomesAttachmentWithoutReplacingText(_ format: NSBitmapImageRep.FileType) throws {
    _ = NSApplication.shared
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                                             bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let data = try #require(bitmap.representation(using: format, properties: [:]))
    let type: NSPasteboard.PasteboardType = switch format {
    case .png: .png
    case .tiff: .tiff
    default: NSPasteboard.PasteboardType("public.jpeg")
    }
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    try #require(pasteboard.setData(data, forType: type))
    let editor = PostingTextView(frame: .zero)
    editor.isRichText = true
    editor.importsGraphics = false
    editor.string = "書きかけ"
    editor.setSelectedRange(NSRange(location: 0, length: 4))
    var attachments: [Data] = []
    editor.addImage = { bytes, _ in attachments.append(bytes) }

    #expect(editor.readablePasteboardTypes.contains(type))
    let preferredType = try #require(editor.preferredPasteboardType(from: pasteboard.types ?? [], restrictedToTypesFrom: nil))
    #expect(editor.readSelection(from: pasteboard, type: preferredType))
    #expect(attachments == [data])
    #expect(editor.string == "書きかけ")
}

@MainActor @Test func copiedImageFilesBecomeAttachmentsAndTextStillPastes() throws {
    _ = NSApplication.shared
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let urls = [URL(fileURLWithPath: "/tmp/first.png"), URL(fileURLWithPath: "/tmp/second.gif")]
    try #require(pasteboard.writeObjects(urls as [NSURL]))
    let editor = PostingTextView(frame: .zero)
    editor.isRichText = true
    editor.importsGraphics = false
    var attachments: [URL] = []
    editor.addFiles = { attachments = $0 }
    let preferredType = try #require(editor.preferredPasteboardType(from: pasteboard.types ?? [], restrictedToTypesFrom: nil))
    #expect(editor.readSelection(from: pasteboard, type: preferredType))
    #expect(attachments == urls)
    #expect(editor.string.isEmpty)

    pasteboard.clearContents()
    try #require(pasteboard.setString("通常のテキスト", forType: .string))
    #expect(editor.readSelection(from: pasteboard, type: .string))
    #expect(editor.string == "通常のテキスト")
    #expect(attachments == urls)

    let formatted = NSAttributedString(RichText.fromMarkdown("**太字**と[リンク](https://example.com)"))
    let rtf = try formatted.data(from: NSRange(location: 0, length: formatted.length),
                                 documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    pasteboard.clearContents()
    try #require(pasteboard.setData(rtf, forType: .rtf))
    editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
    #expect(editor.readSelection(from: pasteboard, type: .rtf))
    #expect(editor.string == "太字とリンク")
    #expect(RichText.slackText(AttributedString(editor.attributedString())) == "*太字*と<https://example.com|リンク>")
}

@MainActor @Test func keyboardFormattingChangesSelectionAndFutureTypingWithoutMarkdownMarkers() throws {
    _ = NSApplication.shared
    let editor = PostingTextView(frame: .zero)
    editor.isRichText = true
    editor.font = RichText.font
    editor.string = "日本語の本文"
    editor.setSelectedRange(NSRange(location: 0, length: 3))
    let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                            timestamp: 0, windowNumber: 0, context: nil,
                                            characters: "b", charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11))
    #expect(editor.performKeyEquivalent(with: event))
    #expect(editor.string == "日本語の本文")
    #expect(RichText.slackText(AttributedString(editor.attributedString())) == "*日本語*の本文")
    editor.formatStrikethrough(nil)
    #expect(RichText.slackText(AttributedString(editor.attributedString())) == "~*日本語*~の本文")
    #expect(editor.performKeyEquivalent(with: event))
    #expect(RichText.slackText(AttributedString(editor.attributedString())) == "~日本語~の本文")
    editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
    editor.typingAttributes = [.font: RichText.font]
    editor.formatItalic(nil)
    editor.insertText("追記", replacementRange: editor.selectedRange())
    #expect(RichText.slackText(AttributedString(editor.attributedString())) == "~日本語~の本文_追記_")
}

@MainActor @Test func formattingUpdatesTheDraftEvenWhenTheCharactersDoNotChange() throws {
    _ = NSApplication.shared
    var text = "本文"
    var richText: AttributedString?
    let view = DraftEditor(text: Binding(get: { text }, set: { text = $0 }),
                           richText: Binding(get: { richText }, set: { richText = $0 }),
                           send: {}, discard: {}, addFiles: { _ in }, addImage: { _, _ in })
    let coordinator = view.makeCoordinator()
    let editor = PostingTextView(frame: .zero)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                          styleMask: .titled, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = editor
    defer { window.close() }
    editor.isRichText = true
    editor.allowsUndo = true
    editor.font = RichText.font
    editor.string = text
    editor.delegate = coordinator
    editor.textStorage?.delegate = coordinator
    editor.undoManager?.removeAllActions()
    editor.setSelectedRange(NSRange(location: 0, length: 2))
    editor.formatBold(nil)
    #expect(text == "本文")
    #expect(RichText.slackText(try #require(richText)) == "*本文*")
    #expect(coordinator.richText == richText)
    let undo = try #require(editor.undoManager)
    #expect(undo.canUndo)
    undo.undo()
    let afterUndo = RichText.slackText(AttributedString(editor.attributedString()))
    let savedAfterUndo = RichText.slackText(try #require(richText))
    #expect(afterUndo == "本文")
    #expect(savedAfterUndo == "本文")
    undo.redo()
    #expect(RichText.slackText(try #require(richText)) == "*本文*")
}
