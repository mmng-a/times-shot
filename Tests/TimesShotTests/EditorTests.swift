import AppKit
import Testing
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
    editor.isRichText = false
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
    editor.isRichText = false
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
}
