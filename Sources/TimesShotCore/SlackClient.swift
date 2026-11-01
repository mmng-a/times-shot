import Foundation
import OSLog

public struct SlackIdentity: Decodable, Sendable {
    public let team: String
    public let user: String
    public let user_id: String
    public let team_id: String
    public let bot_id: String?
}

/// Uses a user token for both text posts and Slack-hosted image uploads. Never retries a publication.
public struct SlackClient: Sendable {
    private static let logger = Logger(subsystem: "jp.sendocorp.TimesShot", category: "Slack")
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

    public func authorize(code: String, verifier: String, clientID: String, now: Date = Date()) async throws -> SlackCredentials {
        let data = try await call("oauth.v2.access", token: "", body: [
            "client_id": clientID, "code": code, "code_verifier": verifier,
            "redirect_uri": SlackAuthorization.redirectURI, "grant_type": "authorization_code"
        ])
        struct Authorization: Decodable {
            struct Team: Decodable { let id: String }
            struct User: Decodable { let id: String; let access_token: String; let refresh_token: String
                let expires_in: Double; let token_type: String; let scope: String }
            let team: Team
            let authed_user: User
        }
        guard let response = try? JSONDecoder().decode(Authorization.self, from: data),
              response.authed_user.token_type == "user", !response.authed_user.access_token.isEmpty,
              !response.authed_user.refresh_token.isEmpty, response.authed_user.expires_in > 0,
              Set(SlackAuthorization.scopes).isSubset(of: Set(response.authed_user.scope.split(separator: ",").map(String.init))) else {
            throw SlackAuthorizationError.invalidResponse
        }
        let identity = try await identity(token: response.authed_user.access_token)
        guard identity.team_id == response.team.id, identity.user_id == response.authed_user.id,
              !identity.team_id.isEmpty, !identity.user_id.isEmpty else { throw SlackAuthorizationError.invalidResponse }
        return SlackCredentials(clientID: clientID, teamID: identity.team_id, userID: identity.user_id,
                                workspace: identity.team, username: identity.user,
                                accessToken: response.authed_user.access_token, refreshToken: response.authed_user.refresh_token,
                                expiresAt: now.addingTimeInterval(response.authed_user.expires_in),
                                refreshExpiresAt: now.addingTimeInterval(30 * 24 * 60 * 60))
    }

    public func refresh(_ credentials: SlackCredentials, now: Date = Date()) async throws -> SlackCredentials {
        let data = try await call("oauth.v2.access", token: "", body: [
            "client_id": credentials.clientID, "grant_type": "refresh_token", "refresh_token": credentials.refreshToken
        ])
        struct Refresh: Decodable { let access_token: String; let refresh_token: String
            let expires_in: Double; let token_type: String; let scope: String }
        guard let response = try? JSONDecoder().decode(Refresh.self, from: data), response.token_type == "user",
              !response.access_token.isEmpty, !response.refresh_token.isEmpty, response.expires_in > 0,
              Set(SlackAuthorization.scopes).isSubset(of: Set(response.scope.split(separator: ",").map(String.init))) else {
            throw SlackAuthorizationError.reconnect
        }
        var updated = credentials
        updated.accessToken = response.access_token
        updated.refreshToken = response.refresh_token
        updated.expiresAt = now.addingTimeInterval(response.expires_in)
        updated.refreshExpiresAt = now.addingTimeInterval(30 * 24 * 60 * 60)
        return updated
    }

    public func channels(token: String) async throws -> [SlackChannel] {
        struct Page: Decodable {
            struct Metadata: Decodable { let next_cursor: String? }
            let channels: [SlackChannel]
            let response_metadata: Metadata?
        }
        var cursor = ""
        var cursors: Set<String> = []
        var channels: [String: SlackChannel] = [:]
        repeat {
            try Task.checkCancellation()
            let data = try await call("users.conversations", token: token, body: [
                "types": "public_channel,private_channel", "exclude_archived": true, "limit": 200, "cursor": cursor
            ])
            let page = try JSONDecoder().decode(Page.self, from: data)
            for channel in page.channels where !channel.is_archived {
                guard channel.id.range(of: "^[CG][A-Z0-9]+$", options: .regularExpression) != nil,
                      !channel.name.isEmpty else { throw SlackAuthorizationError.invalidResponse }
                channels[channel.id] = channel
            }
            cursor = page.response_metadata?.next_cursor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !cursor.isEmpty, !cursors.insert(cursor).inserted { throw SlackAuthorizationError.invalidResponse }
        } while !cursor.isEmpty
        return channels.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func send(_ post: PendingPost, accessToken: @Sendable () async throws -> String) async throws {
        let text = post.draft.richText.map(RichText.slackText) ?? SlackMarkdown.convert(post.draft.text)
        if post.draft.images.isEmpty {
            _ = try await call("chat.postMessage", token: try await accessToken(), body: [
                "channel": post.channelID, "text": text, "mrkdwn": true,
                "unfurl_links": false, "unfurl_media": false, "client_msg_id": post.id.uuidString
            ], publishes: true)
            return
        }

        var files: [[String: String]] = []
        for image in post.draft.images {
            try Task.checkCancellation()
            let bytes: Data
            do { bytes = try Data(contentsOf: image.fileURL, options: .mappedIfSafe) }
            catch {
                Self.logger.error("Image read failed: domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code)")
                throw error
            }
            let response = try await call("files.getUploadURLExternal", token: try await accessToken(), body: [
                "filename": image.filename, "length": bytes.count
            ])
            struct Upload: Decodable { let upload_url: URL; let file_id: String }
            let upload: Upload
            do { upload = try JSONDecoder().decode(Upload.self, from: response) }
            catch {
                Self.logger.error("files.getUploadURLExternal: invalid upload response")
                throw error
            }
            guard upload.upload_url.scheme == "https",
                  let host = upload.upload_url.host,
                  host == "files.slack.com" || host.hasSuffix(".slack.com") else {
                Self.logger.error("files.getUploadURLExternal: unexpected upload destination")
                throw DeliveryError.rejected("Slackの画像アップロード先を確認できませんでした。")
            }
            var request = URLRequest(url: upload.upload_url)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            // The signed upload URL needs no OAuth token.
            let result: URLResponse
            do { (_, result) = try await session.upload(for: request, from: bytes) }
            catch {
                Self.logger.error("Image upload failed: domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code)")
                throw error
            }
            guard let http = result as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                Self.logger.error("Image upload failed: HTTP=\((result as? HTTPURLResponse)?.statusCode ?? 0)")
                throw DeliveryError.rejected("画像をアップロードできませんでした。")
            }
            files.append(["id": upload.file_id, "title": image.filename])
        }
        try Task.checkCancellation()
        _ = try await call("files.completeUploadExternal", token: try await accessToken(), body: [
            "files": files, "channel_id": post.channelID, "initial_comment": text
        ], publishes: true)
    }

    private func call(
        _ method: String, token: String, body: [String: Any], publishes: Bool = false
    ) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://slack.com/api/\(method)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if method == "users.conversations" {
            var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            url.queryItems = body.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
            request.url = url.url
            request.httpMethod = "GET"
        } else if method == "files.getUploadURLExternal" || method == "oauth.v2.access" {
            var form = URLComponents()
            form.queryItems = body.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        } else {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            Self.logger.error("\(method, privacy: .public): transport failed domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code)")
            if publishes { throw DeliveryError.unknown }
            throw DeliveryError.rejected("Slackと通信できませんでした。接続を確認してください。")
        }
        guard let http = response as? HTTPURLResponse else {
            Self.logger.error("\(method, privacy: .public): missing HTTP response")
            throw DeliveryError.unknown
        }
        let requestID = http.value(forHTTPHeaderField: "x-slack-req-id") ?? "unavailable"
        let result = try? JSONDecoder().decode(APIResult.self, from: data)
        if !(200..<300).contains(http.statusCode) || result?.ok != true {
            let details = method == "oauth.v2.access" ? "" : Self.diagnosticDetails(result?.response_metadata?.messages ?? [], token: token)
            Self.logger.error("\(method, privacy: .public): HTTP=\(http.statusCode) request_id=\(requestID, privacy: .public) error=\(result?.error ?? "invalid_response", privacy: .public) details=\(details, privacy: .public)")
        }
        if http.statusCode == 429 {
            let message = publishes || method.hasPrefix("files.")
                ? "Slackの送信制限に達しました。この投稿は破棄しました。"
                : "Slackの利用制限に達しました。しばらく待ってから操作してください。"
            throw DeliveryError.rejected(message)
        }
        guard (200..<300).contains(http.statusCode) else {
            if publishes { throw DeliveryError.unknown }
            throw DeliveryError.rejected("Slackへの接続でエラーが発生しました（HTTP \(http.statusCode)）。")
        }
        guard let result else { throw DeliveryError.unknown }
        guard result.ok else {
            let code = result.error ?? "unknown_error"
            if ["internal_error", "fatal_error", "request_timeout", "service_unavailable"].contains(code), publishes {
                throw DeliveryError.unknown
            }
            let message: String
            switch code {
            case "invalid_auth", "token_revoked", "token_expired", "not_authed", "invalid_refresh_token", "missing_scope", "account_inactive":
                throw SlackAuthorizationError.reconnect
            case "channel_not_found", "not_in_channel", "no_permission", "posting_to_channel_denied":
                message = "選択したチャンネルに投稿できません。参加状況を確認し、チャンネルを選び直してください。"
            case "msg_too_long": message = "本文が長すぎるため投稿できません。"
            default:
                if method == "oauth.v2.access" { message = "Slackに接続できませんでした。接続をやり直してください。" }
                else if publishes || method.hasPrefix("files.") { message = "Slackへの送信に失敗しました（\(code)）。" }
                else { message = "Slackの操作に失敗しました（\(code)）。" }
            }
            throw DeliveryError.rejected(message)
        }
        return data
    }

    private struct APIResult: Decodable {
        let ok: Bool
        let error: String?
        let response_metadata: Metadata?

        struct Metadata: Decodable { let messages: [String]? }
    }

    static func diagnosticDetails(_ messages: [String], token: String) -> String {
        var details = messages.joined(separator: "; ")
        if !token.isEmpty { details = details.replacingOccurrences(of: token, with: "<redacted>") }
        return details.replacingOccurrences(of: #"https?://[^\s<>\"']+|xox[baprs]-[A-Za-z0-9-]+|xoxe[.\-][A-Za-z0-9.\-]+"#,
                                            with: "<redacted>", options: .regularExpression)
    }
}
