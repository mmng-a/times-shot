import Foundation
import Testing
@testable import TimesShotCore

@Test(arguments: [
    ("**太字** *斜体* ~~取消~~", "*太字* _斜体_ ~取消~"),
    ("[説明](https://example.com?a=1&b=2)", "<https://example.com?a=1&amp;b=2|説明>"),
    ("`**そのまま**`", "`**そのまま**`"),
    ("> **引用**\n- 項目\n1. 項目", "> *引用*\n- 項目\n1. 項目"),
    ("```swift\nlet x = a < b && c > d\n```", "```\nlet x = a &lt; b &amp;&amp; c &gt; d\n```"),
    ("一行目\n\n三行目  ", "一行目\n\n三行目  "),
    ("```\n**未完了**", "```\n**未完了**\n```")
])
func markdown(input: String, expected: String) {
    #expect(SlackMarkdown.convert(input) == expected)
}

@Test func emptyDraftAndNotification() {
    #expect(Draft(text: " \n\t").isEmpty)
    let image = ImageAttachment(filename: "screen.png", fileURL: URL(filePath: "/tmp/screen.png"))
    #expect(!Draft(images: [image]).isEmpty)
    #expect(Draft(text: "調査結果\n次の対応", images: [image]).notificationSummary == "「調査結果 次の対応」\n画像1枚：screen.png")
}

private actor SenderProbe {
    var texts: [String] = []
    var active = 0
    var maximumActive = 0

    func send(_ post: PendingPost) async throws {
        active += 1
        maximumActive = max(maximumActive, active)
        texts.append(post.draft.text)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(5))
        if post.draft.text == "失敗" { throw DeliveryError.rejected("test") }
    }
}

@MainActor @Test func queueKeepsOrderAndContinuesAfterFailure() async {
    let probe = SenderProbe()
    var results: [String] = []
    var failures = 0
    var queue: PostingQueue!
    await withCheckedContinuation { done in
        queue = PostingQueue(send: { try await probe.send($0) }, completed: { post, error in
            results.append(post.draft.text)
            if error != nil { failures += 1 }
            if results.count == 3 { done.resume() }
        })
        for text in ["最初", "失敗", "最後"] {
            queue.enqueue(PendingPost(draft: Draft(text: text), channelID: "C123", token: "test"))
        }
        #expect(queue.count == 3)
    }
    #expect(results == ["最初", "失敗", "最後"])
    #expect(await probe.texts == results)
    #expect(await probe.maximumActive == 1)
    #expect(failures == 1)
    #expect(queue.count == 0)
}

@MainActor @Test func discardCancelsWorkerAndWaitingPosts() async {
    var finished = false
    var queue: PostingQueue!
    await withCheckedContinuation { started in
        queue = PostingQueue(send: { _ in
            started.resume()
            try await Task.sleep(for: .seconds(60))
        }, completed: { _, _ in finished = true })
        queue.enqueue(PendingPost(draft: Draft(text: "最初"), channelID: "C1", token: "test"))
        queue.enqueue(PendingPost(draft: Draft(text: "次"), channelID: "C1", token: "test"))
    }
    queue.discardAll()
    #expect(queue.count == 0)
    await Task.yield()
    #expect(!finished)
}
