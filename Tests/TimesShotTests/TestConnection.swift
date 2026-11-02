import Foundation
import TimesShotCore
@testable import TimesShot

func testCredentials(teamID: String = "T1", userID: String = "U1", expiresAt: Date = .distantFuture,
                     connectionID: UUID = UUID()) -> SlackCredentials {
    SlackCredentials(clientID: "1.2", teamID: teamID, userID: userID, workspace: "Workspace", username: "user",
                     accessToken: "test-access", refreshToken: "test-refresh", expiresAt: expiresAt,
                     refreshExpiresAt: .distantFuture, connectionID: connectionID)
}

@MainActor func testConnection(connected: Bool = true) -> SlackConnection {
    SlackConnection(clientID: "1.2", read: { connected ? testCredentials() : nil }, save: { _ in })
}

func testSlackClient() -> SlackClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [EmptyChannelsProtocol.self]
    return SlackClient(session: URLSession(configuration: configuration))
}

private final class EmptyChannelsProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                                                           httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"ok":true,"channels":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
