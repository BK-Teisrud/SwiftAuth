import Auth
import Foundation
import Testing

@testable import ExampleAuthApp

private final class BackendTestProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url!.path
    let status: Int
    let body: String
    if path.contains("rejected") {
      status = 401
      body = "sensitive-backend-error"
    } else if path.contains("unavailable") {
      status = 503
      body = "sensitive-backend-error"
    } else if path.contains("wrong-user") {
      status = 200
      body =
        "{\"subject\":\"other\",\"accessToken\":\"app-access\",\"expiresAt\":\(Date().addingTimeInterval(600).timeIntervalSince1970),\"refreshToken\":\"new-refresh\"}"
    } else if path.contains("oversized") {
      status = 200
      body = String(repeating: "x", count: 65_537)
    } else if path.hasSuffix("begin") {
      status = 200
      body = #"{"transactionID":"single-use-transaction"}"#
    } else if path.hasSuffix("me") {
      status = request.value(forHTTPHeaderField: "Authorization") == "Bearer app-access" ? 200 : 401
      body = #"{"subject":"internal-user","githubLogin":"octocat"}"#
    } else {
      status = 200
      body =
        "{\"subject\":\"internal-user\",\"accessToken\":\"app-access\",\"expiresAt\":\(Date().addingTimeInterval(600).timeIntervalSince1970),\"refreshToken\":\"new-refresh\"}"
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

struct BackendTransportTests {
  private func backend(_ variant: String = "") -> AppAuthBackend {
    AppAuthBackend(
      baseURL: URL(string: "https://api.example.com/\(variant)")!,
      applicationID: "example-app", protocolClasses: [BackendTestProtocol.self])
  }

  @Test func transactionAndProfileUseBackendContract() async throws {
    let backend = backend()
    let transaction = try await backend.begin(
      provider: .github, state: "state", nonce: nil,
      codeChallenge: "challenge", redirectURI: URL(string: "exampleauthapp://auth/callback")!)
    #expect(transaction.id == "single-use-transaction")
    let user = try await backend.user(accessToken: "app-access")
    #expect(user.subject == "internal-user")
    #expect(user.githubLogin == "octocat")
  }

  @Test func refreshReturnsBackendIdentityAndRotatedToken() async throws {
    let backend = backend()
    let identity = AuthIdentity(issuer: backend.baseURL.absoluteString, subject: "internal-user")
    let response = try await backend.refresh(token: "old-refresh", identity: identity)
    #expect(response.identity == identity)
    #expect(response.refreshToken == "new-refresh")
  }

  @Test func rejectionAndUnknownRotationStayDistinct() async throws {
    for (variant, error) in [
      ("rejected", AuthError.refreshRejected), ("unavailable", .refreshOutcomeUnknown),
    ] {
      let backend = backend(variant)
      await #expect(throws: error) {
        try await backend.refresh(
          token: "old-refresh",
          identity: .init(issuer: backend.baseURL.absoluteString, subject: "internal-user"))
      }
    }
  }

  @Test func refreshCannotChangeUser() async throws {
    let backend = backend("wrong-user")
    await #expect(throws: AuthError.refreshRejected) {
      try await backend.refresh(
        token: "old-refresh",
        identity: .init(issuer: backend.baseURL.absoluteString, subject: "internal-user"))
    }
  }

  @Test func oversizedResponsesAreRejected() async throws {
    let backend = backend("oversized")
    await #expect(throws: AuthError.tokenExchange) {
      try await backend.user(accessToken: "app-access")
    }
  }
}
