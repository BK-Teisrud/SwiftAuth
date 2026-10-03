import AuthenticationServices
import CryptoKit
import Foundation
import Testing

@testable import Auth

@MainActor private final class DirectBackendStub: DirectAuthBackend {
  var challenge: String?
  var state: String?
  var proof: DirectAuthProof?
  var exchanges = 0
  var wrongIdentity = false
  func begin(
    provider: DirectAuthProvider, state: String, nonce: String?, codeChallenge: String?,
    redirectURI: URL
  ) async throws -> DirectAuthTransaction {
    self.state = state
    challenge = codeChallenge
    return .init(id: "transaction")
  }
  func exchange(_ proof: DirectAuthProof) async throws -> AuthTokenResponse {
    self.proof = proof
    exchanges += 1
    return tokens()
  }
  func refresh(token: String, identity: AuthIdentity) async throws -> AuthTokenResponse { tokens() }
  func tokens() -> AuthTokenResponse {
    .init(
      identity: .init(issuer: "https://api.example.com", subject: wrongIdentity ? "other" : "user"),
      accessToken: "app-access", expiresAt: Date().addingTimeInterval(600),
      refreshToken: "app-refresh")
  }
}

@MainActor private final class DirectAppleStub: DirectAppleAuthorization {
  func authorize(nonce: String, state: String) async throws -> ASAuthorizationAppleIDCredential {
    throw AuthError.cancelled
  }
  func cancel() {}
}

@MainActor private final class DirectBrowserStub: AuthBrowserSession {
  var authorizationURL: URL?
  var issuer: String?
  var badState = false
  var duplicateCode = false
  var onAuthorization: (() async -> Void)?
  func authenticate(url: URL, callbackURI: URL, ephemeral: Bool) async throws -> URL {
    authorizationURL = url
    await onAuthorization?()
    let fields = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
    let state = fields.first { $0.name == "state" }!.value!
    var callback = URLComponents(url: callbackURI, resolvingAgainstBaseURL: false)!
    callback.queryItems = [
      .init(name: "state", value: badState ? "wrong" : state),
      .init(name: "code", value: "provider-code"),
    ]
    if let issuer { callback.queryItems!.append(.init(name: "iss", value: issuer)) }
    if duplicateCode { callback.queryItems!.append(.init(name: "code", value: "second")) }
    return callback.url!
  }
  func cancel() {}
}

@MainActor @Suite struct DirectAuthTests {
  private func adapter(_ backend: DirectBackendStub, _ browser: DirectBrowserStub) throws
    -> DirectAuthAdapter
  {
    try DirectAuthAdapter(
      backendURL: URL(string: "https://api.example.com")!,
      applicationID: "app", githubClientID: "github-public-id",
      redirectURI: URL(string: "com.example.app://callback")!, keychainNamespace: "direct-tests",
      backend: backend, apple: DirectAppleStub(), browser: browser)
  }

  @Test func githubUsesDirectAuthorizationPKCEAndBackendSession() async throws {
    let backend = DirectBackendStub()
    let browser = DirectBrowserStub()
    let adapter = try adapter(backend, browser)
    let client = AuthClient(
      configuration: adapter.configuration, service: adapter, storage: MemoryStorage())
    try await client.login(choice: .connection("github"))
    #expect(try await client.validAccessToken() == "app-access")
    #expect(browser.authorizationURL?.host == "github.com")
    let proof = try #require(backend.proof)
    let verifier = try #require(proof.codeVerifier)
    #expect(backend.challenge == OIDCEncoding.base64(Data(SHA256.hash(data: Data(verifier.utf8)))))
    #expect(proof.authorizationCode == "provider-code")
    #expect(proof.identityToken == nil)
    #expect(proof.description == "DirectAuthProof(<REDACTED>)")
    #expect(
      await client.state == .signedIn(.init(issuer: "https://api.example.com", subject: "user")))
    #expect(adapter.configuration.storageService != (try configuration()).storageService)
  }

  @Test func githubIssuerIdentificationIsAccepted() async throws {
    let backend = DirectBackendStub()
    let browser = DirectBrowserStub()
    browser.issuer = "https://github.com/login/oauth"
    let adapter = try adapter(backend, browser)
    let response = try await adapter.login(choice: .connection("github"))
    #expect(response.accessToken == "app-access")
    #expect(backend.exchanges == 1)
  }

  @Test func unexpectedGithubIssuerNeverReachesExchange() async throws {
    for issuer in [
      "https://github.com", "https://attacker.example.com/login/oauth",
      "https://github.com/login/oauth/",
    ] {
      let backend = DirectBackendStub()
      let browser = DirectBrowserStub()
      browser.issuer = issuer
      let adapter = try adapter(backend, browser)
      await #expect(throws: AuthError.callback) {
        try await adapter.login(choice: .connection("github"))
      }
      #expect(backend.exchanges == 0)
    }
  }

  @Test func invalidCallbacksNeverReachExchange() async throws {
    for duplicate in [false, true] {
      let backend = DirectBackendStub()
      let browser = DirectBrowserStub()
      browser.badState = !duplicate
      browser.duplicateCode = duplicate
      let adapter = try adapter(backend, browser)
      await #expect(throws: AuthError.callback) {
        try await adapter.login(choice: .connection("github"))
      }
      #expect(backend.exchanges == 0)
    }
  }

  @Test func cancellationRejectsLateCallback() async throws {
    let backend = DirectBackendStub()
    let browser = DirectBrowserStub()
    let adapter = try adapter(backend, browser)
    browser.onAuthorization = { await adapter.cancelLogin() }
    await #expect(throws: AuthError.operationInvalidated) {
      try await adapter.login(choice: .connection("github"))
    }
    #expect(backend.exchanges == 0)
  }

  @Test func refreshCannotSwitchInternalUser() async throws {
    let backend = DirectBackendStub()
    backend.wrongIdentity = true
    let adapter = try adapter(backend, DirectBrowserStub())
    await #expect(throws: AuthError.refreshRejected) {
      try await adapter.refresh(
        token: "refresh", identity: .init(issuer: "https://api.example.com", subject: "user"),
        nonce: nil, binding: nil)
    }
  }

  @Test func appleCancellationAndUnsupportedChoice() async throws {
    let adapter = try adapter(DirectBackendStub(), DirectBrowserStub())
    await #expect(throws: AuthError.cancelled) {
      try await adapter.login(choice: .connection("apple"))
    }
    await #expect(throws: AuthError.unsupportedProviderFeature) {
      try await adapter.login(choice: .serviceSelection)
    }
  }
}
