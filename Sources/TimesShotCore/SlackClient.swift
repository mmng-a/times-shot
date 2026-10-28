import Foundation

public struct SlackIdentity: Decodable, Sendable {
    public let team: String
    public let user: String
    public let user_id: String
    public let bot_id: String?
}

/// Uses a user token for both text posts and Slack-hosted image uploads. Never retries a publication.
public struct SlackClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func identity(token: String) async throws -> SlackIdentity {
        let data = try await call("auth.test", token: token, body: [:])
        let identity = try JSONDecoder().decode(SlackIdentity.self, from: data)
        guard identity.bot_id == nil else {
            throw DeliveryError.rejected("本人名義のUser OAuth Tokenを設定してください。Bot Tokenは使用できません。")
        }
        return identity
    }

    public func send(_ post: PendingPost) async throws {
        let text = post.draft.richText.map(RichText.slackText) ?? SlackMarkdown.convert(post.draft.text)
        if post.draft.images.isEmpty {
            _ = try await call("chat.postMessage", token: post.token, body: [
                "channel": post.channelID, "text": text, "mrkdwn": true,
                "unfurl_links": false, "unfurl_media": false, "client_msg_id": post.id.uuidString
            ], publishes: true)
            return
        }

        var files: [[String: String]] = []
        for image in post.draft.images {
            try Task.checkCancellation()
            let bytes = try Data(contentsOf: image.fileURL, options: .mappedIfSafe)
            let response = try await call("files.getUploadURLExternal", token: post.token, body: [
                "filename": image.filename, "length": bytes.count
            ])
            struct Upload: Decodable { let upload_url: URL; let file_id: String }
            let upload = try JSONDecoder().decode(Upload.self, from: response)
            guard upload.upload_url.scheme == "https",
                  let host = upload.upload_url.host,
                  host == "files.slack.com" || host.hasSuffix(".slack.com") else {
                throw DeliveryError.rejected("Slackの画像アップロード先を確認できませんでした。")
            }
            var request = URLRequest(url: upload.upload_url)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            // The signed upload URL needs no OAuth token.
            let (_, result) = try await session.upload(for: request, from: bytes)
            guard let http = result as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw DeliveryError.rejected("画像をアップロードできませんでした。")
            }
            files.append(["id": upload.file_id, "title": image.filename])
        }
        try Task.checkCancellation()
        _ = try await call("files.completeUploadExternal", token: post.token, body: [
            "files": files, "channel_id": post.channelID, "initial_comment": text
        ], publishes: true)
    }

    private func call(
        _ method: String, token: String, body: [String: Any], publishes: Bool = false
    ) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://slack.com/api/\(method)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if publishes { throw DeliveryError.unknown }
            throw DeliveryError.rejected("Slackと通信できませんでした。接続を確認してください。")
        }
        guard let http = response as? HTTPURLResponse else { throw DeliveryError.unknown }
        if http.statusCode == 429 {
            throw DeliveryError.rejected("Slackの送信制限に達しました。この投稿は破棄しました。")
        }
        guard (200..<300).contains(http.statusCode) else {
            if publishes { throw DeliveryError.unknown }
            throw DeliveryError.rejected("Slackへの接続でエラーが発生しました（HTTP \(http.statusCode)）。")
        }
        struct Result: Decodable { let ok: Bool; let error: String? }
        guard let result = try? JSONDecoder().decode(Result.self, from: data) else {
            throw DeliveryError.unknown
        }
        guard result.ok else {
            let code = result.error ?? "unknown_error"
            if ["internal_error", "fatal_error", "request_timeout", "service_unavailable"].contains(code), publishes {
                throw DeliveryError.unknown
            }
            let message: String
            switch code {
            case "invalid_auth", "token_revoked", "token_expired", "not_authed":
                message = "Slackの認証情報を設定し直してください。"
            case "missing_scope": message = "Slackアプリに必要な権限がありません。"
            case "channel_not_found", "not_in_channel", "no_permission", "posting_to_channel_denied":
                message = "設定したチャンネルに投稿できません。参加状況とチャンネルIDを確認してください。"
            case "msg_too_long": message = "本文が長すぎるため投稿できません。"
            default: message = "Slackへの送信に失敗しました（\(code)）。"
            }
            throw DeliveryError.rejected(message)
        }
        return data
    }
}
