import CryptoKit
import Foundation
import Security

public enum SlackAuthorizationError: Error, LocalizedError, Equatable, Sendable {
    case invalidCallback, denied, invalidResponse, reconnect, changedConnection

    public var errorDescription: String? {
        switch self {
        case .invalidCallback: "Slackからの接続結果を確認できませんでした。接続をやり直してください。"
        case .denied: "Slackへの接続が許可されませんでした。"
        case .invalidResponse: "Slackの認証情報を確認できませんでした。接続をやり直してください。"
        case .reconnect: "Slackに再接続してください。"
        case .changedConnection: "Slackの接続先が変わったため、操作を中止しました。"
        }
    }
}

/// A single authorization attempt. The verifier never leaves memory except in the token exchange.
public struct SlackAuthorization: Sendable {
    public static let redirectURI = "timesshot://oauth/callback"
    public static let scopes = ["chat:write", "files:write", "channels:read", "groups:read"]
    public let state: String
    public let verifier: String

    public init() throws {
        func random() throws -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw SlackAuthorizationError.invalidResponse
            }
            return Self.base64URL(Data(bytes))
        }
        state = try random()
        verifier = try random()
    }

    init(state: String, verifier: String) { self.state = state; self.verifier = verifier }

    public func url(clientID: String) -> URL {
        var url = URLComponents(string: "https://slack.com/oauth/v2/authorize")!
        url.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "user_scope", value: Self.scopes.joined(separator: ",")),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return url.url!
    }

    public func code(from callback: URL) throws -> String {
        guard let url = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              url.scheme == "timesshot", url.host == "oauth", url.path == "/callback",
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil else {
            throw SlackAuthorizationError.invalidCallback
        }
        let items = url.queryItems ?? []
        func value(_ name: String) -> String? {
            let matches = items.filter { $0.name == name }
            return matches.count == 1 ? matches.first?.value : nil
        }
        guard value("state") == state else { throw SlackAuthorizationError.invalidCallback }
        if items.contains(where: { $0.name == "error" }) { throw SlackAuthorizationError.denied }
        guard let code = value("code"), !code.isEmpty else {
            throw SlackAuthorizationError.invalidCallback
        }
        return code
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// Stored as one Keychain item so access and refresh tokens are replaced together.
public struct SlackCredentials: Codable, Equatable, Sendable {
    public var connectionID: UUID
    public let clientID: String
    public let teamID: String
    public let userID: String
    public let workspace: String
    public let username: String
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var refreshExpiresAt: Date

    public init(clientID: String, teamID: String, userID: String, workspace: String, username: String,
                accessToken: String, refreshToken: String, expiresAt: Date, refreshExpiresAt: Date,
                connectionID: UUID = UUID()) {
        self.clientID = clientID; self.teamID = teamID; self.userID = userID
        self.workspace = workspace; self.username = username
        self.accessToken = accessToken; self.refreshToken = refreshToken
        self.expiresAt = expiresAt; self.refreshExpiresAt = refreshExpiresAt
        self.connectionID = connectionID
    }
}

public struct SlackChannel: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let is_private: Bool
    public let is_archived: Bool

}
