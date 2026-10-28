import Foundation
import Testing
@testable import TimesShotCore

private final class MockHTTP: @unchecked Sendable {
    static let shared = MockHTTP()
    private let lock = NSLock()
    private var replies: [String?] = []
    private var recorded: [URLRequest] = []

    func reset(_ replies: [String?]) { lock.withLock { self.replies = replies; recorded = [] } }
    var requests: [URLRequest] { lock.withLock { recorded } }
    func accept(_ request: URLRequest) -> String? {
        var request = request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            request.httpBody = body
        }
        return lock.withLock {
            recorded.append(request)
            return replies.isEmpty ? nil : replies.removeFirst()
        }
    }
}

private final class MockProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let reply = MockHTTP.shared.accept(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                                                           httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct SlackClientTests {
    private func client() -> SlackClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProtocol.self]
        return SlackClient(session: URLSession(configuration: configuration))
    }

    @Test func textPostsOnceAndTimeoutIsUnknown() async {
        MockHTTP.shared.reset([nil])
        do {
            try await client().send(PendingPost(draft: Draft(text: "**メモ**"), channelID: "C123", token: "user-token"))
            Issue.record("timeout must fail")
        } catch DeliveryError.unknown {} catch { Issue.record("unexpected error: \(error)") }
        let requests = MockHTTP.shared.requests
        #expect(requests.count == 1)
        #expect(requests.first?.url?.lastPathComponent == "chat.postMessage")
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer user-token")
    }

    @Test func richTextIsConvertedForTextPosts() async throws {
        MockHTTP.shared.reset([#"{"ok":true}"#])
        let content = RichText.fromMarkdown("**太字**と[リンク](https://example.com)")
        try await client().send(PendingPost(draft: Draft(text: String(content.characters), richText: content),
                                           channelID: "C123", token: "user-token"))
        let body = try #require(MockHTTP.shared.requests.first?.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["text"] as? String == "*太字*と<https://example.com|リンク>")
    }

    @Test func imagesAndTextPublishTogetherAfterAllUploads() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let image = ImageAttachment(filename: "photo.png", fileURL: file)
        MockHTTP.shared.reset([
            #"{"ok":true,"upload_url":"https://files.slack.com/upload/one","file_id":"F1"}"#,
            "OK",
            #"{"ok":true,"upload_url":"https://files.slack.com/upload/two","file_id":"F2"}"#,
            "OK",
            #"{"ok":true}"#
        ])
        let content = RichText.fromMarkdown("**画像の説明**")
        try await client().send(PendingPost(draft: Draft(text: "画像の説明", images: [image, image], richText: content), channelID: "C123", token: "user-token"))
        let requests = MockHTTP.shared.requests
        #expect(requests.map { $0.url!.lastPathComponent } == ["files.getUploadURLExternal", "one", "files.getUploadURLExternal", "two", "files.completeUploadExternal"])
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(requests[3].value(forHTTPHeaderField: "Authorization") == nil)
        let body = try #require(requests.last?.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["initial_comment"] as? String == "*画像の説明*")
    }

    @Test func failedUploadDoesNotPublishTextOrRetry() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        MockHTTP.shared.reset([#"{"ok":true,"upload_url":"https://files.slack.com/upload/one","file_id":"F1"}"#, nil])
        await #expect(throws: (any Error).self) {
            try await client().send(PendingPost(draft: Draft(text: "本文", images: [ImageAttachment(filename: "image.png", fileURL: file)]), channelID: "C1", token: "test"))
        }
        #expect(MockHTTP.shared.requests.count == 2)
        #expect(!MockHTTP.shared.requests.contains { $0.url?.lastPathComponent == "chat.postMessage" || $0.url?.lastPathComponent == "files.completeUploadExternal" })
    }

    @Test func botIdentityIsRejected() async {
        MockHTTP.shared.reset([#"{"ok":true,"team":"Workspace","user":"bot","user_id":"U1","bot_id":"B1"}"#])
        await #expect(throws: DeliveryError.self) { try await client().identity(token: "bot-token") }
    }
}
