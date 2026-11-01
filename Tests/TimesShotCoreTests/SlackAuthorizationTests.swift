import Foundation
import Testing
@testable import TimesShotCore

@Test func pkceUsesTheRFCChallengeAndRequestsOnlyUserScopes() throws {
    let authorization = SlackAuthorization(state: "test-state", verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
    let url = try #require(URLComponents(url: authorization.url(clientID: "1.2"), resolvingAgainstBaseURL: false))
    let items = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(url.host == "slack.com")
    #expect(url.path == "/oauth/v2/authorize")
    #expect(items["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    #expect(items["code_challenge_method"] == "S256")
    #expect(items["user_scope"] == "chat:write,files:write,channels:read,groups:read")
    #expect(items["scope"] == nil)
    #expect(items["client_secret"] == nil)
    #expect(items["code_verifier"] == nil)
    let first = try SlackAuthorization()
    let second = try SlackAuthorization()
    #expect(first.state != second.state)
    #expect(first.verifier != second.verifier)
    #expect(first.verifier.count == 43)
}

@Test(arguments: [
    "timesshot://oauth/callback?state=wrong&code=one",
    "timesshot://oauth/wrong?state=expected&code=one",
    "other://oauth/callback?state=expected&code=one",
    "timesshot://wrong/callback?state=expected&code=one",
    "timesshot://oauth/callback?state=expected&state=expected&code=one",
    "timesshot://oauth/callback?state=expected&state&code=one",
    "timesshot://oauth/callback?state=expected&code=one&code=two",
    "timesshot://oauth/callback?state=expected&code=",
    "timesshot://oauth/callback?state=expected&code=one#fragment",
    "timesshot://user@oauth/callback?state=expected&code=one"
])
func untrustedOAuthCallbacksAreRejected(callback: String) throws {
    let authorization = SlackAuthorization(state: "expected", verifier: "verifier")
    #expect(throws: SlackAuthorizationError.self) { try authorization.code(from: #require(URL(string: callback))) }
}

@Test func callbackReturnsOnlyACodeWithAMatchingStateAndHandlesDenial() throws {
    let authorization = SlackAuthorization(state: "expected", verifier: "verifier")
    #expect(try authorization.code(from: #require(URL(string: "timesshot://oauth/callback?state=expected&code=one"))) == "one")
    #expect(throws: SlackAuthorizationError.denied) {
        try authorization.code(from: #require(URL(string: "timesshot://oauth/callback?state=expected&error=access_denied")))
    }
}
