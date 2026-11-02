import Foundation
import Testing
import TimesShotCore
@testable import TimesShot

private final class ConnectionHTTP: @unchecked Sendable {
    static let shared = ConnectionHTTP()
    private let lock = NSLock()
    private var response = ""
    private var held = false
    private var started: (@Sendable () -> Void)?
    private var waiting: [ConnectionProtocol] = []
    private var recorded: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { recorded } }

    func reset(_ response: String, held: Bool = false, started: (@Sendable () -> Void)? = nil) {
        lock.withLock {
            self.response = response; self.held = held; self.started = started
            waiting = []; recorded = []
        }
    }

    func accept(_ transport: ConnectionProtocol) {
        let (response, callback): (String?, (@Sendable () -> Void)?) = lock.withLock {
            recorded.append(transport.request)
            let callback = started
            started = nil
            if held { waiting.append(transport) }
            return (held ? nil : self.response, callback)
        }
        callback?()
        if let response { transport.respond(response) }
    }

    func release() {
        let (waiting, response) = lock.withLock {
            let result = (self.waiting, self.response)
            self.waiting = []; held = false
            return result
        }
        for transport in waiting { transport.respond(response) }
    }
}

private final class ConnectionProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { ConnectionHTTP.shared.accept(self) }
    override func stopLoading() {}

    func respond(_ response: String) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                                                           httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized)
@MainActor struct SlackConnectionTests {
    private let refreshed = #"{"ok":true,"access_token":"new-access","refresh_token":"new-refresh","expires_in":43200,"token_type":"user","scope":"chat:write,files:write,channels:read,groups:read"}"#

    private func client() -> SlackClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConnectionProtocol.self]
        return SlackClient(session: URLSession(configuration: configuration))
    }

    @Test func simultaneousOperationsShareOneRefreshAndPersistBothTokens() async throws {
        let original = testCredentials(expiresAt: .distantPast)
        var saved: [SlackCredentials?] = []
        let connection = SlackConnection(clientID: "1.2", client: client(), read: { original }, save: { saved.append($0) })
        var first: Task<String, Error>!
        await withCheckedContinuation { started in
            ConnectionHTTP.shared.reset(refreshed, held: true, started: { started.resume() })
            first = Task { try await connection.accessToken(for: original.connectionID) }
        }
        let second = Task { try await connection.accessToken(for: original.connectionID) }
        await Task.yield()
        ConnectionHTTP.shared.release()
        #expect(try await first.value == "new-access")
        #expect(try await second.value == "new-access")
        #expect(ConnectionHTTP.shared.requests.count == 1)
        #expect(saved.count == 1)
        let persisted = try #require(saved.first ?? nil)
        #expect(persisted.refreshToken == "new-refresh")
        #expect(connection.credentials?.connectionID == original.connectionID)
        #expect(try await connection.accessToken(for: original.connectionID) == "new-access")
        #expect(ConnectionHTTP.shared.requests.count == 1)
    }

    @Test func disconnectDuringRefreshCannotRestoreCredentialsOrReturnAToken() async throws {
        let original = testCredentials(expiresAt: .distantPast)
        var saved: [SlackCredentials?] = []
        let connection = SlackConnection(clientID: "1.2", client: client(), read: { original }, save: { saved.append($0) })
        var operation: Task<String, Error>!
        await withCheckedContinuation { started in
            ConnectionHTTP.shared.reset(refreshed, held: true, started: { started.resume() })
            operation = Task { try await connection.accessToken(for: original.connectionID) }
        }
        try connection.disconnect()
        ConnectionHTTP.shared.release()
        await #expect(throws: SlackAuthorizationError.changedConnection) { try await operation.value }
        #expect(connection.credentials == nil)
        #expect(saved.count == 1)
        #expect(saved[0] == nil)
    }

    @Test func revokedRefreshRequiresReconnectAndDoesNotRetry() async throws {
        ConnectionHTTP.shared.reset(#"{"ok":false,"error":"invalid_refresh_token"}"#)
        let original = testCredentials(expiresAt: .distantPast)
        let connection = SlackConnection(clientID: "1.2", client: client(), read: { original }, save: { _ in })
        for _ in 0..<2 {
            await #expect(throws: SlackAuthorizationError.reconnect) { try await connection.accessToken(for: original.connectionID) }
        }
        #expect(connection.requiresReconnect)
        #expect(ConnectionHTTP.shared.requests.count == 1)
    }

    @Test func failedKeychainWriteDoesNotReuseARedeemedRefreshToken() async throws {
        ConnectionHTTP.shared.reset(refreshed)
        let original = testCredentials(expiresAt: .distantPast)
        let connection = SlackConnection(clientID: "1.2", client: client(), read: { original },
                                             save: { _ in throw StorageError.message("test write failure") })
        await #expect(throws: StorageError.self) { try await connection.accessToken(for: original.connectionID) }
        #expect(connection.credentials?.refreshToken == "new-refresh")
        #expect(connection.requiresReconnect)
        await #expect(throws: SlackAuthorizationError.reconnect) { try await connection.accessToken(for: original.connectionID) }
        #expect(ConnectionHTTP.shared.requests.count == 1)
    }

    @Test func postsBoundToAnotherConnectionNeverReceiveTheCurrentToken() async throws {
        let connection = testConnection()
        await #expect(throws: SlackAuthorizationError.changedConnection) { try await connection.accessToken(for: UUID()) }
        try connection.replace(testCredentials())
        #expect(!connection.requiresReconnect)
    }

    @Test func channelSelectionRegistersNamesAndIDsAndRejectsStaleChoices() async throws {
        ConnectionHTTP.shared.reset(#"{"ok":true,"channels":[{"id":"C00000001","name":"times","is_private":false,"is_archived":false},{"id":"G00000002","name":"private","is_private":true,"is_archived":false}]}"#)
        let suite = "TimesShotChannelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let app = AppModel(storage: try DraftStorage(directory: directory), defaults: defaults, connection: testConnection())
        try app.connect(testCredentials())
        let settings = SettingsModel(app: app, applyShortcut: { _ in }, client: client())
        await settings.reloadChannels()
        #expect(settings.channelError == nil)
        #expect(settings.availableChannels.count == 2)
        settings.channelSearch = "TIMES"
        #expect(settings.filteredChannels.map(\.name) == ["times"])
        let channel = try #require(settings.filteredChannels.first)
        settings.addChannel(channel)
        #expect(app.configuration.selectedChannel?.channelID == "C00000001")
        #expect(app.configuration.selectedChannel?.name == "times")
        settings.addChannel(channel)
        #expect(settings.channelError != nil)
        #expect(app.configuration.channels.count == 1)
        try app.connect(testCredentials(teamID: "T2"))
        settings.addChannel(channel)
        #expect(settings.channelError != nil)
        #expect(app.configuration.channels.isEmpty)
    }
}
