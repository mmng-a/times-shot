import AppKit
import Testing
@testable import TimesShotCore

@Test func richTextSendsVisibleFormattingAndPreservesOverlappingStyles() {
    #expect(RichText.slackText(AttributedString()) == "")
    let bold = NSFont(descriptor: RichText.font.fontDescriptor.withSymbolicTraits(.bold), size: 15)!
    let both = NSFont(descriptor: RichText.font.fontDescriptor.withSymbolicTraits([.bold, .italic]), size: 15)!
    let text = NSMutableAttributedString(string: "abcdef", attributes: [.font: bold])
    text.addAttribute(.font, value: both, range: NSRange(location: 2, length: 2))
    text.addAttribute(.kern, value: 0.5, range: NSRange(location: 3, length: 1))
    #expect(RichText.slackText(AttributedString(text)) == "*ab_cd_ef*")

    text.append(NSAttributedString(string: "\n取消", attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue]))
    text.append(NSAttributedString(string: "\ncode *literal*", attributes: [.font: RichText.codeFont]))
    text.append(NSAttributedString(string: "\nリンク", attributes: [.link: URL(string: "https://example.com?a=1&b=2")!]))
    #expect(RichText.slackText(AttributedString(text)) == "*ab_cd_ef*\n~取消~\n```\ncode *literal*\n```\n<https://example.com?a=1&amp;b=2|リンク>")
}

@Test(arguments: [
    "**太字** *斜体* ~~取消~~",
    "一行目\n\n三行目  ",
    "> **引用**\n- 項目\n1. 項目",
    "`**そのまま**`",
    "前文\n```swift\nlet x = a < b && c > d\nlet y = 1\n```\n後文",
    "```\n一行のコード\n```",
    "```\n**未完了**"
])
func legacyMarkdownDraftRetainsItsFormatting(_ markdown: String) {
    #expect(RichText.slackText(RichText.fromMarkdown(markdown)) == SlackMarkdown.convert(markdown))
}

@Test func nativeFormattingSurvivesDraftSerializationAndOldDraftsStillLoad() throws {
    let content = RichText.fromMarkdown("**太字**と[リンク](https://example.com)")
    let draft = Draft(text: String(content.characters), richText: content)
    let reloaded = try JSONDecoder().decode(Draft.self, from: JSONEncoder().encode(draft))
    #expect(reloaded.text == draft.text)
    #expect(reloaded.images == draft.images)
    #expect(RichText.slackText(try #require(reloaded.richText)) == "*太字*と<https://example.com|リンク>")
    let old = try JSONDecoder().decode(Draft.self, from: Data(#"{"text":"**以前の下書き**","images":[]}"#.utf8))
    #expect(old.richText == nil)
    #expect(String(RichText.fromMarkdown(old.text).characters) == "以前の下書き")
}
