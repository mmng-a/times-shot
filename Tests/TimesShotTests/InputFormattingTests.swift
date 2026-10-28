import AppKit
import Testing
import TimesShotCore
@testable import TimesShot

@MainActor private func inputEditor() -> PostingTextView {
    _ = NSApplication.shared
    let editor = PostingTextView(frame: .zero)
    editor.isRichText = true
    editor.allowsUndo = true
    editor.font = RichText.font
    editor.typingAttributes = [.font: RichText.font, .foregroundColor: NSColor.textColor]
    return editor
}

@MainActor private func type(_ text: String, in editor: PostingTextView) {
    for character in text { editor.insertText(String(character), replacementRange: editor.selectedRange()) }
}

@MainActor @Test(arguments: [
    ("*test*", "test", "*test*"),
    ("**test**", "test", "*test*"),
    ("_test_", "test", "_test_"),
    ("~test~", "test", "~test~"),
    ("~~test~~", "test", "~test~"),
    ("`*test*`", "*test*", "`*test*`"),
    ("文 *日本語😀*", "文 日本語😀", "文 *日本語😀*")
])
func typedDelimitersBecomeFormattingAndDoNotFormatFollowingText(_ input: String, _ visible: String, _ posted: String) {
    let editor = inputEditor()
    type(input, in: editor)
    #expect(editor.string == visible)
    #expect(RichText.slackText(AttributedString(editor.attributedString())) == posted)
    type(" next", in: editor)
    #expect(editor.string == visible + " next")
    #expect(RichText.slackText(AttributedString(editor.attributedString())) == posted + " next")
}

@MainActor @Test func listsContinueEndAndSurviveSaving() throws {
    let editor = inputEditor()
    type("- test", in: editor)
    #expect(editor.string == "•\ttest")
    let style = try #require(editor.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
    #expect(style.textLists.count == 1)
    editor.insertNewline(nil)
    type("*次*", in: editor)
    let draft = Draft(text: editor.string, richText: AttributedString(editor.attributedString()))
    let saved = try JSONDecoder().decode(Draft.self, from: JSONEncoder().encode(draft))
    let restored = inputEditor()
    restored.textStorage?.setAttributedString(NSAttributedString(try #require(saved.richText)))
    restored.setSelectedRange(NSRange(location: (restored.string as NSString).length, length: 0))
    restored.insertNewline(nil)
    #expect(restored.string == "•\ttest\n•\t次\n•\t")
    restored.insertNewline(nil)
    type("普通", in: restored)
    #expect(restored.string == "•\ttest\n•\t次\n普通")
    #expect(RichText.slackText(AttributedString(restored.attributedString())) == "• test\n• *次*\n普通")
    #expect((restored.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.textLists.isEmpty == true)
}

@MainActor @Test func backspaceAtListStartRemovesListFormatting() {
    let editor = inputEditor()
    type("- test", in: editor)
    editor.setSelectedRange(NSRange(location: 2, length: 0))
    editor.deleteBackward(nil)
    #expect(editor.string == "test")
    #expect((editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.textLists.isEmpty == true)
}

@MainActor @Test func codeEscapesAndIMECompositionAreNotRewrittenPrematurely() {
    let editor = inputEditor()
    type("\\*test*", in: editor)
    #expect(editor.string == "\\*test*")
    editor.string = ""
    editor.typingAttributes = [.font: RichText.codeFont]
    type("- *test*", in: editor)
    #expect(editor.string == "- *test*")
    editor.string = ""
    editor.typingAttributes = [.font: RichText.font]
    editor.setMarkedText("*にほん*", selectedRange: NSRange(location: 5, length: 0),
                         replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(editor.string == "*にほん*")
    #expect(editor.hasMarkedText())
    editor.insertText("*日本語*", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
    #expect(editor.string == "日本語")
    #expect(RichText.slackText(AttributedString(editor.attributedString())) == "*日本語*")
}

@MainActor @Test func automaticFormattingCanBeUndoneAndRedone() throws {
    let editor = inputEditor()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                          styleMask: .titled, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = editor
    defer { window.close() }
    let undo = try #require(editor.undoManager)
    undo.groupsByEvent = false
    for character in "*test*" {
        undo.beginUndoGrouping()
        editor.insertText(String(character), replacementRange: editor.selectedRange())
        undo.endUndoGrouping()
    }
    undo.undo()
    #expect(editor.string == "*test")
    undo.redo()
    #expect(editor.string == "test")
    #expect(RichText.slackText(AttributedString(editor.attributedString())) == "*test*")
}
