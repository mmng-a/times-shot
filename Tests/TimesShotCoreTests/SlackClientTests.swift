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
                                                           httpVersion: nil, headerFields: ["x-slack-req-id": "times-shot-test-request"])!, cacheStoragePolicy: .notAllowed)
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
            try await client().send(PendingPost(draft: Draft(text: "**メモ**"), channelID: "C123", connectionID: UUID()), accessToken: { "user-token" })
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
                                           channelID: "C123", connectionID: UUID()), accessToken: { "user-token" })
        let body = try #require(MockHTTP.shared.requests.first?.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["text"] as? String == "*太字*と<https://example.com|リンク>")
    }

    @Test func imagesAndTextPublishTogetherAfterAllUploads() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let image = ImageAttachment(filename: "画像 + &=?#.png", fileURL: file)
        MockHTTP.shared.reset([
            #"{"ok":true,"upload_url":"https://files.slack.com/upload/one","file_id":"F1"}"#,
            "OK",
            #"{"ok":true,"upload_url":"https://files.slack.com/upload/two","file_id":"F2"}"#,
            "OK",
            #"{"ok":true}"#
        ])
        let content = RichText.fromMarkdown("**画像の説明**")
        try await client().send(PendingPost(draft: Draft(text: "画像の説明", images: [image, image], richText: content), channelID: "C123", connectionID: UUID()), accessToken: { "user-token" })
        let requests = MockHTTP.shared.requests
        #expect(requests.map { $0.url!.lastPathComponent } == ["files.getUploadURLExternal", "one", "files.getUploadURLExternal", "two", "files.completeUploadExternal"])
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(requests[3].value(forHTTPHeaderField: "Authorization") == nil)
        let uploadRequest = requests[0]
        #expect(uploadRequest.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded; charset=utf-8")
        let formBody = try #require(uploadRequest.httpBody)
        var form = URLComponents()
        form.percentEncodedQuery = String(decoding: formBody, as: UTF8.self)
        let fields = Dictionary(uniqueKeysWithValues: try #require(form.queryItems).map { ($0.name, $0.value) })
        #expect(fields["filename"] == image.filename)
        #expect(fields["length"] == "3")
        #expect(!String(decoding: formBody, as: UTF8.self).contains("+"))
        #expect(requests.last?.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8")
        let body = try #require(requests.last?.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["initial_comment"] as? String == "*画像の説明*")
    }

    @Test(arguments: [false, true])
    func invalidArgumentsAreRejectedWithoutExposingDetailsOrRetrying(atCompletion: Bool) async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let failure = #"{"ok":false,"error":"invalid_arguments","response_metadata":{"messages":["[ERROR] missing required field: length"]}}"#
        MockHTTP.shared.reset(atCompletion ? [
            #"{"ok":true,"upload_url":"https://files.slack.com/upload/one","file_id":"F1"}"#,
            "OK", failure
        ] : [failure])
        do {
            try await client().send(PendingPost(draft: Draft(images: [ImageAttachment(filename: "image.png", fileURL: file)]),
                                               channelID: "C123", connectionID: UUID()), accessToken: { "test" })
            Issue.record("invalid arguments must fail")
        } catch DeliveryError.rejected(let message) {
            #expect(message == "Slackへの送信に失敗しました（invalid_arguments）。")
            #expect(!message.contains("length"))
        } catch { Issue.record("unexpected error: \(error)") }
        #expect(MockHTTP.shared.requests.count == (atCompletion ? 3 : 1))
    }

    @Test func diagnosticsKeepValidationDetailsAndRedactCredentialsAndURLs() {
        let details = SlackClient.diagnosticDetails([
            "[ERROR] missing required field: length",
            "invalid field [json-pointer:/files/0/id]",
            "token=secret-value xoxp-example-123 https://files.slack.com/upload/signed?secret=value"
        ], token: "secret-value")
        #expect(details.contains("missing required field: length"))
        #expect(details.contains("[json-pointer:/files/0/id]"))
        #expect(!details.contains("secret-value"))
        #expect(!details.contains("xoxp-example-123"))
        #expect(!details.contains("https://"))
        #expect(SlackClient.diagnosticDetails([], token: "") == "")
    }

    @Test func failedUploadDoesNotPublishTextOrRetry() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        MockHTTP.shared.reset([#"{"ok":true,"upload_url":"https://files.slack.com/upload/one","file_id":"F1"}"#, nil])
        await #expect(throws: (any Error).self) {
            try await client().send(PendingPost(draft: Draft(text: "本文", images: [ImageAttachment(filename: "image.png", fileURL: file)]), channelID: "C1", connectionID: UUID()), accessToken: { "test" })
        }
        #expect(MockHTTP.shared.requests.count == 2)
        #expect(!MockHTTP.shared.requests.contains { $0.url?.lastPathComponent == "chat.postMessage" || $0.url?.lastPathComponent == "files.completeUploadExternal" })
    }

    @Test func botIdentityIsRejected() async {
        MockHTTP.shared.reset([#"{"ok":true,"team":"Workspace","team_id":"T1","user":"bot","user_id":"U1","bot_id":"B1"}"#])
        await #expect(throws: DeliveryError.self) { try await client().identity(token: "bot-token") }
    }

    @Test func oauthExchangesCodeWithoutASecretAndStoresTheUserIdentity() async throws {
        MockHTTP.shared.reset([
            #"{"ok":true,"team":{"id":"T1"},"authed_user":{"id":"U1","scope":"chat:write,files:write,channels:read,groups:read","access_token":"xoxe.xoxp-access","refresh_token":"refresh-one","expires_in":43200,"token_type":"user"}}"#,
            #"{"ok":true,"team":"Workspace","team_id":"T1","user":"user","user_id":"U1"}"#
        ])
        let now = Date(timeIntervalSince1970: 100)
        let credentials = try await client().authorize(code: "code+&", verifier: "verifier+&", clientID: "1.2", now: now)
        #expect(credentials.teamID == "T1")
        #expect(credentials.userID == "U1")
        #expect(credentials.accessToken == "xoxe.xoxp-access")
        #expect(credentials.refreshToken == "refresh-one")
        #expect(credentials.expiresAt == now.addingTimeInterval(43200))
        let request = try #require(MockHTTP.shared.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("code=code%2B%26"))
        #expect(body.contains("code_verifier=verifier%2B%26"))
        #expect(!body.contains("client_secret"))
        #expect(MockHTTP.shared.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer xoxe.xoxp-access")
    }

    @Test func oauthRejectsInsufficientScopesBeforeUsingTheToken() async {
        MockHTTP.shared.reset([
            #"{"ok":true,"team":{"id":"T1"},"authed_user":{"id":"U1","scope":"chat:write","access_token":"access","refresh_token":"refresh","expires_in":43200,"token_type":"user"}}"#
        ])
        await #expect(throws: SlackAuthorizationError.invalidResponse) {
            try await client().authorize(code: "code", verifier: "verifier", clientID: "1.2")
        }
        #expect(MockHTTP.shared.requests.count == 1)
    }

    @Test func channelsFollowEveryCursorAndExcludeArchivedDuplicates() async throws {
        MockHTTP.shared.reset([
            #"{"ok":true,"channels":[{"id":"C1","name":"times","is_private":false,"is_archived":false}],"response_metadata":{"next_cursor":"next+&"}}"#,
            #"{"ok":true,"channels":[{"id":"C1","name":"times","is_private":false,"is_archived":false},{"id":"G1","name":"private","is_private":true,"is_archived":false},{"id":"C2","name":"old","is_private":false,"is_archived":true}],"response_metadata":{"next_cursor":""}}"#
        ])
        let channels = try await client().channels(token: "user-token")
        #expect(channels.map(\.id) == ["G1", "C1"])
        #expect(channels.first?.is_private == true)
        let request = try #require(MockHTTP.shared.requests.last)
        #expect(request.httpMethod == "GET")
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        let query = components.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "cursor", value: "next+&")))
        #expect(query.contains(URLQueryItem(name: "types", value: "public_channel,private_channel")))
        #expect(MockHTTP.shared.requests.count == 2)
    }

    @Test func channelsDoNotReturnPartialResultsWhenALaterPageFails() async {
        MockHTTP.shared.reset([
            #"{"ok":true,"channels":[],"response_metadata":{"next_cursor":"next"}}"#,
            #"{"ok":false,"error":"missing_scope"}"#
        ])
        await #expect(throws: SlackAuthorizationError.reconnect) { try await client().channels(token: "user-token") }
    }
}
