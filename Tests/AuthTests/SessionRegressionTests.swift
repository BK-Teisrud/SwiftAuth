import Foundation
import Networking
import Testing

@testable import Auth

@MainActor private final class SessionFixtureAdapter: AuthOIDCAdapter {
  let configuration: AuthConfiguration
  var subject = "user-A"
  var lifetime: TimeInterval = 600
  var refreshes = 0
  var loginFailure: AuthError?
  init(_ configuration: AuthConfiguration) { self.configuration = configuration }
  var identity: AuthIdentity {
    .init(issuer: configuration.issuer.absoluteString, subject: subject)
  }
  func login(choice: AuthLoginChoice) async throws -> AuthTokenResponse {
    if let loginFailure { throw loginFailure }
    return .init(
      identity: identity, accessToken: subject, expiresAt: Date().addingTimeInterval(lifetime),
      refreshToken: "refresh")
  }
  func cancelLogin() async {}
  func refresh(token: String, identity: AuthIdentity, nonce: String?, binding: AuthIDTokenBinding?)
    async throws -> AuthTokenResponse
  {
    refreshes += 1
    return .init(
      identity: identity, accessToken: "refresh-\(refreshes)",
      expiresAt: Date().addingTimeInterval(lifetime), refreshToken: "replacement")
  }
  func logoutAtProvider() async throws {}
}
private actor Delayed401: HTTPTransport {
  var pending: CheckedContinuation<Void, Never>?
  private(set) var tokens: [String] = []
  func send(_ request: URLRequest, redirectPolicy: RedirectPolicy) async throws -> HTTPResponse {
    tokens.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
    let first = tokens.count == 1
    if first { await withCheckedContinuation { pending = $0 } }
    return .init(data: Data(), metadata: .init(statusCode: first ? 401 : 200, url: request.url))
  }
  var waiting: Bool { pending != nil }
  func resume() {
    pending?.resume()
    pending = nil
  }
}
@Suite @MainActor struct SessionRegressionTests {
  @Test func oldRequestCannotReplayAfterAccountSwitch() async throws {
    let config = try configuration()
    let adapter = SessionFixtureAdapter(config)
    let auth = AuthClient(configuration: config, service: adapter, storage: MemoryStorage())
    try await auth.login()
    let transport = Delayed401()
    let api = HTTPClient(
      configuration: try ClientConfiguration(
        baseURL: URL(string: "https://api-one.example.com/")!, transport: transport,
        credentialProvider: AuthCredentialProvider(client: auth)))
    let request = Task {
      try await api.execute(HTTPRequest(pathSegments: ["protected"], requiresAuthentication: true))
    }
    while !(await transport.waiting) { await Task.yield() }
    try await auth.logout()
    adapter.subject = "user-B"
    try await auth.login()
    await transport.resume()
    await #expect(throws: NetworkingError.self) { _ = try await request.value }
    #expect(await transport.tokens == ["Bearer user-A"])
    let freshProvider = AuthCredentialProvider(client: auth)
    #expect(try await freshProvider.bearerToken() == "user-B")
  }
  @Test func shortLivedTokenWithRefreshIsReused() async throws {
    let config = try configuration()
    let adapter = SessionFixtureAdapter(config)
    adapter.lifetime = 30
    let auth = AuthClient(configuration: config, service: adapter, storage: MemoryStorage())
    try await auth.login()
    for _ in 0..<3 { _ = try await auth.validAccessToken() }
    #expect(adapter.refreshes == 0)
  }
  @Test func failedLoginPreservesReauthenticationRequirement() async throws {
    let config = try configuration()
    let adapter = SessionFixtureAdapter(config)
    let storage = MemoryStorage()
    try storage.save(.init(identity: adapter.identity, refreshToken: "old", refreshRejected: true))
    let auth = AuthClient(configuration: config, service: adapter, storage: storage)
    try await auth.restoreSession()
    #expect(
      await auth.state == .reauthenticationRequired(adapter.identity, reason: .refreshRejected))
    adapter.loginFailure = .providerRejected
    await #expect(throws: AuthError.providerRejected) { try await auth.login() }
    #expect(
      await auth.state == .reauthenticationRequired(adapter.identity, reason: .refreshRejected))
    await #expect(throws: AuthError.refreshRejected) { try await auth.validAccessToken() }
  }
  @Test func delayedRejectionWithinSameSessionReusesRotatedToken() async throws {
    let config = try configuration()
    let adapter = SessionFixtureAdapter(config)
    let auth = AuthClient(configuration: config, service: adapter, storage: MemoryStorage())
    try await auth.login()
    let provider = AuthCredentialProvider(client: auth)
    let old = try await provider.bearerToken()
    let fresh = try await provider.recover(rejectedToken: old)
    #expect(try await provider.recover(rejectedToken: old) == fresh)
    #expect(adapter.refreshes == 1)
  }
  @Test func providerCannotRebindEvenWhenNextLoginReturnsSameToken() async throws {
    let config = try configuration()
    let adapter = SessionFixtureAdapter(config)
    let auth = AuthClient(configuration: config, service: adapter, storage: MemoryStorage())
    try await auth.login()
    let provider = AuthCredentialProvider(client: auth)
    let old = try await provider.bearerToken()
    try await auth.logout()
    try await auth.login()
    await #expect(throws: AuthError.operationInvalidated) {
      try await provider.recover(rejectedToken: old)
    }
    await #expect(throws: AuthError.operationInvalidated) { try await provider.bearerToken() }
  }
  @Test func cancelledReauthenticationPreservesRequirement() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    let storage = MemoryStorage()
    try storage.save(.init(identity: adapter.identity, refreshToken: "old", refreshRejected: true))
    let auth = AuthClient(configuration: adapter.configuration, service: adapter, storage: storage)
    try await auth.restoreSession()
    adapter.holdLogin = true
    let login = Task { try await auth.login() }
    while adapter.heldLogin == nil { await Task.yield() }
    await auth.cancelLogin()
    #expect(
      await auth.state == .reauthenticationRequired(adapter.identity, reason: .refreshRejected))
    adapter.heldLogin?.resume(returning: adapter.tokens())
    await #expect(throws: AuthError.operationInvalidated) { try await login.value }
  }
  @Test func cancellingOneWaiterDoesNotCancelSharedRefresh() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    adapter.holdRefresh = true
    let storage = MemoryStorage()
    try storage.save(.init(identity: adapter.identity, refreshToken: "old"))
    let auth = AuthClient(configuration: adapter.configuration, service: adapter, storage: storage)
    try await auth.restoreSession()
    let cancelled = Task { try await auth.validAccessToken() }
    while adapter.heldRefresh == nil { await Task.yield() }
    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    let remaining = Task { try await auth.validAccessToken() }
    adapter.heldRefresh?.resume(returning: adapter.tokens(access: "fresh"))
    #expect(try await remaining.value == "fresh")
    #expect(adapter.refreshCount == 1)
  }
  @Test func refreshDeadlineQuarantinesAndIgnoresLateResult() async throws {
    let config = try AuthConfiguration(
      issuer: URL(string: "https://issuer.example.com/")!, clientID: "one",
      redirectURI: URL(string: "com.example.one://callback")!,
      apiResource: .auth0Audience("api-one"),
      keychainNamespace: "test.deadline", refreshTimeout: 3)
    let adapter = FakeAdapter(configuration: config)
    adapter.holdRefresh = true
    let storage = MemoryStorage()
    try storage.save(.init(identity: adapter.identity, refreshToken: "old"))
    let auth = AuthClient(configuration: config, service: adapter, storage: storage)
    try await auth.restoreSession()
    await #expect(throws: AuthError.refreshOutcomeUnknown) { try await auth.validAccessToken() }
    #expect(try storage.load()?.refreshInFlight == true)
    adapter.heldRefresh?.resume(returning: adapter.tokens(access: "too-late"))
    try await Task.sleep(for: .milliseconds(30))
    #expect(try storage.load()?.refreshToken == "old")
    await #expect(throws: AuthError.refreshOutcomeUnknown) { try await auth.validAccessToken() }
  }

  @Test func prerequisiteDeadlineIsRetryableAndLatePreparationCannotReplaceState() async throws {
    let config = try AuthConfiguration(
      issuer: URL(string: "https://issuer.example.com/")!, clientID: "one",
      redirectURI: URL(string: "com.example.one://callback")!,
      apiResource: .auth0Audience("api-one"),
      keychainNamespace: "test.prepare-deadline", refreshTimeout: 3)
    let adapter = FakeAdapter(configuration: config)
    adapter.holdPreparation = true
    let storage = MemoryStorage()
    try storage.save(.init(identity: adapter.identity, refreshToken: "old"))
    let auth = AuthClient(configuration: config, service: adapter, storage: storage)
    try await auth.restoreSession()
    await #expect(throws: AuthError.networkUnavailable) { try await auth.validAccessToken() }
    #expect(try storage.load()?.refreshInFlight == false)
    #expect(adapter.refreshCount == 0)
    adapter.holdPreparation = false
    #expect(try await auth.validAccessToken() == "new-access-1")
    adapter.heldPreparation?.resume()
    try await Task.sleep(for: .milliseconds(20))
    #expect(await auth.state == .signedIn(adapter.identity))
    #expect(adapter.refreshCount == 1)
  }
  @Test func expiredSessionWithoutRefreshRemainsReauthAfterLoginFailure() async throws {
    let clock = RegressionClock()
    let adapter = FakeAdapter(configuration: try configuration())
    adapter.providesRefreshToken = false
    let auth = AuthClient(
      configuration: adapter.configuration, service: adapter, storage: MemoryStorage(),
      now: { clock.now() })
    try await auth.login()
    clock.advance(1000)
    await #expect(throws: AuthError.reauthenticationRequired) { try await auth.validAccessToken() }
    adapter.holdLogin = true
    let failed = Task { try await auth.login() }
    while adapter.heldLogin == nil { await Task.yield() }
    adapter.heldLogin?.resume(throwing: AuthError.providerRejected)
    await #expect(throws: AuthError.providerRejected) { try await failed.value }
    #expect(
      await auth.state
        == .reauthenticationRequired(adapter.identity, reason: .reauthenticationRequired))
  }

}

private final class RegressionClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Date()
  func now() -> Date { lock.withLock { value } }
  func advance(_ seconds: TimeInterval) {
    lock.withLock { value = value.addingTimeInterval(seconds) }
  }
}
