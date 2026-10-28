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
