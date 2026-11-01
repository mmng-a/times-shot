import AuthenticationServices
import Observation
import TimesShotCore

/// Owns one connection and serializes refreshes, including concurrent channel loads and posts.
@MainActor @Observable
final class SlackConnection {
    private(set) var credentials: SlackCredentials?
    private(set) var requiresReconnect = false
    let clientID: String
    @ObservationIgnored private let client: SlackClient
    @ObservationIgnored private let save: @MainActor (SlackCredentials?) throws -> Void
    @ObservationIgnored private var refreshTask: Task<String, Error>?

    init(clientID: String = Bundle.main.object(forInfoDictionaryKey: "SlackClientID") as? String ?? "",
         client: SlackClient = SlackClient(),
         read: @MainActor () throws -> SlackCredentials? = TokenStore.read,
         save: @escaping @MainActor (SlackCredentials?) throws -> Void = TokenStore.save) throws {
        self.clientID = clientID
        self.client = client
        self.save = save
        credentials = try read()
        if let credentials { requiresReconnect = credentials.clientID != clientID }
    }

    func replace(_ credentials: SlackCredentials) throws {
        guard refreshTask == nil else { throw StorageError.message("Slackへの接続を更新中です。完了してから操作してください。") }
        try save(credentials)
        self.credentials = credentials
        requiresReconnect = false
    }

    func disconnect() throws {
        try save(nil)
        credentials = nil
        requiresReconnect = false
        // An in-flight refresh must finish before a new connection can replace it.
    }

    func markForReconnect(connectionID: UUID) {
        if credentials?.connectionID == connectionID { requiresReconnect = true }
    }

    func accessToken(for connectionID: UUID, now: Date = Date()) async throws -> String {
        guard let current = credentials, current.connectionID == connectionID else {
            throw SlackAuthorizationError.changedConnection
        }
        guard !requiresReconnect else { throw SlackAuthorizationError.reconnect }
        if let refreshTask {
            let token = try await refreshTask.value
            guard credentials?.connectionID == connectionID else { throw SlackAuthorizationError.changedConnection }
            return token
        }
        guard current.expiresAt.timeIntervalSince(now) <= 60 else { return current.accessToken }
        guard current.refreshExpiresAt > now else {
            requiresReconnect = true
            throw SlackAuthorizationError.reconnect
        }
        let task = Task { @MainActor in
            defer { refreshTask = nil }
            do {
                let updated = try await client.refresh(current, now: now)
                guard credentials?.connectionID == current.connectionID else { throw SlackAuthorizationError.changedConnection }
                // Never reuse the previous refresh token after Slack has exchanged it.
                credentials = updated
                do { try save(updated) }
                catch { requiresReconnect = true; throw error }
                return updated.accessToken
            } catch {
                if case SlackAuthorizationError.reconnect = error { markForReconnect(connectionID: connectionID) }
                throw error
            }
        }
        refreshTask = task
        let token = try await task.value
        guard credentials?.connectionID == connectionID else { throw SlackAuthorizationError.changedConnection }
        return token
    }
}

/// Keeps the system authentication session alive until it returns or the user cancels.
@MainActor
final class SlackWebAuthentication: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private weak var window: NSWindow?

    func authenticate(url: URL, window: NSWindow) async throws -> URL {
        guard session == nil else { throw StorageError.message("Slackへの接続を開始しています。") }
        self.window = window
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme("timesshot"),
                                                     completionHandler: completionHandler(continuation))
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: StorageError.message("Slackの接続画面を開けませんでした。"))
            }
        }
    }

    /// AuthenticationServices delivers replies on an XPC queue, outside the main actor.
    nonisolated func completionHandler(_ continuation: CheckedContinuation<URL, Error>) -> @Sendable (URL?, Error?) -> Void {
        { [weak self] url, error in
            Task { @MainActor in
                self?.session = nil
                if let error { continuation.resume(throwing: error) }
                else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: SlackAuthorizationError.invalidCallback) }
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window ?? ASPresentationAnchor()
    }
}
