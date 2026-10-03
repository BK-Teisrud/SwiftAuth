import Foundation
import Testing

@testable import Auth

func configuration(
  namespace: String = "com.example.one.production", issuer: String = "https://issuer.example.com/",
  clientID: String = "one", audience: String = "api-one", trustedAudiences: [String] = []
) throws -> AuthConfiguration {
  try AuthConfiguration(
    issuer: URL(string: issuer)!, clientID: clientID,
    redirectURI: URL(string: "com.example.one://callback")!, apiResource: .auth0Audience(audience),
    keychainNamespace: namespace, trustedIDTokenAudiences: trustedAudiences)
}

final class MemoryStorage: SessionStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var value: StoredSession?
  private var failure: AuthError?
  private var writes = 0
  private var logoutPending = false
  func hasPendingLogout() throws -> Bool { lock.withLock { logoutPending } }
  func markLogoutPending() throws { lock.withLock { logoutPending = true } }
  func clearPendingLogout() throws { lock.withLock { logoutPending = false } }
  func fail(_ error: AuthError?) { lock.withLock { failure = error } }
  func load() throws -> StoredSession? {
    try lock.withLock {
      if let failure { throw failure }
      return value
    }
  }
  func save(_ session: StoredSession) throws {
    try lock.withLock {
      if let failure { throw failure }
      value = session
      writes += 1
    }
  }
  func remove() throws {
    try lock.withLock {
      if let failure { throw failure }
      value = nil
    }
  }
}

@MainActor final class FakeAdapter: AuthOIDCAdapter {
  let configuration: AuthConfiguration
  var refreshCount = 0
  var cancelCount = 0
  var prepareFailure: AuthError?
  var holdPreparation = false
  var heldPreparation: CheckedContinuation<Void, Never>?
  var holdCancel = false
  var heldCancel: CheckedContinuation<Void, Never>?
  var now: () -> Date = { Date() }
  var tokenLifetime: TimeInterval = 600
  var providesRefreshToken = true
  var refreshFailure: AuthError?
  var failStorageAfterRefresh: MemoryStorage?
  var holdLogin = false
  var heldLogin: CheckedContinuation<AuthTokenResponse, Error>?
  var holdRefresh = false
  var heldRefresh: CheckedContinuation<AuthTokenResponse, Error>?
  var rotatedToken: String? = "rotated"
  init(configuration: AuthConfiguration) { self.configuration = configuration }
  var identity: AuthIdentity {
    .init(issuer: configuration.issuer.absoluteString, subject: "synthetic-user")
  }
  func tokens(access: String = "synthetic-access", expires: Date = Date().addingTimeInterval(600))
    -> AuthTokenResponse
  {
    .init(
      identity: identity, accessToken: access, expiresAt: expires,
      refreshToken: providesRefreshToken ? "synthetic-refresh" : nil
    )
  }
  func login(choice: AuthLoginChoice) async throws -> AuthTokenResponse {
    if holdLogin { return try await withCheckedThrowingContinuation { heldLogin = $0 } }
    return tokens(expires: now().addingTimeInterval(tokenLifetime))
  }
  func cancelLogin() async {
    cancelCount += 1
    if holdCancel { await withCheckedContinuation { heldCancel = $0 } }
  }
  func prepareRefresh() async throws {
    if holdPreparation { await withCheckedContinuation { heldPreparation = $0 } }
    if let prepareFailure { throw prepareFailure }
  }
  func refresh(token: String, identity: AuthIdentity, nonce: String?, binding: AuthIDTokenBinding?)
    async throws
    -> AuthTokenResponse
  {
    refreshCount += 1
    if holdRefresh { return try await withCheckedThrowingContinuation { heldRefresh = $0 } }
    try await Task.sleep(for: .milliseconds(20))
    if let refreshFailure { throw refreshFailure }
    failStorageAfterRefresh?.fail(.keychain(status: -25308))
    return .init(
      identity: identity, accessToken: "new-access-\(refreshCount)",
      expiresAt: Date().addingTimeInterval(600), refreshToken: rotatedToken)
  }
  func logoutAtProvider() async throws { throw AuthError.unsupportedProviderFeature }
}

@Suite @MainActor struct SessionTests {
  @Test func loginRestoreAndRedactedState() async throws {
    let config = try configuration()
    let adapter = FakeAdapter(configuration: try configuration())
    let store = MemoryStorage()
    let client = AuthClient(configuration: config, service: adapter, storage: store)
    try await client.login()
    #expect(try await client.validAccessToken() == "synthetic-access")
    #expect(await client.state == .signedIn(adapter.identity))
    let publicState = String(reflecting: await client.state)
    #expect(!publicState.contains("synthetic-access") && !publicState.contains("synthetic-refresh"))
    #expect(!String(reflecting: adapter.tokens()).contains("synthetic-refresh"))
    let restored = AuthClient(configuration: config, service: adapter, storage: store)
    try await restored.restoreSession()
    #expect(await restored.state == .signedIn(adapter.identity))
    #expect(try await restored.validAccessToken() == "new-access-1")
  }

  @Test func concurrentRefreshRotationAndDelayed401() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    let store = MemoryStorage()
    try store.save(.init(identity: adapter.identity, refreshToken: "original"))
    let client = AuthClient(configuration: adapter.configuration, service: adapter, storage: store)
    try await client.restoreSession()
    let values = try await withThrowingTaskGroup(of: String.self) { group in
      for _ in 0..<20 { group.addTask { try await client.validAccessToken() } }
      var result: [String] = []
      for try await value in group { result.append(value) }
      return result
    }
    #expect(Set(values) == ["new-access-1"])
    #expect(adapter.refreshCount == 1)
    #expect(try store.load()?.refreshToken == "rotated")
    #expect(try store.load()?.refreshInFlight == false)
    await #expect(throws: AuthError.operationInvalidated) {
      try await client.recover(rejectedToken: "old-access")
    }
    #expect(adapter.refreshCount == 1)
  }

  @Test func missingRefreshReplacementKeepsOriginal() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    let store = MemoryStorage()
    adapter.rotatedToken = nil
    try store.save(.init(identity: adapter.identity, refreshToken: "original"))
    let client = AuthClient(configuration: adapter.configuration, service: adapter, storage: store)
    try await client.restoreSession()
    _ = try await client.validAccessToken()
    #expect(try store.load()?.refreshToken == "original")
  }

  @Test(arguments: [AuthError.refreshRejected, .refreshOutcomeUnknown])
  func refreshFailuresDoNotRetryAcrossRestore(_ failure: AuthError) async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    let store = MemoryStorage()
    adapter.refreshFailure = failure
    try store.save(.init(identity: adapter.identity, refreshToken: "original"))
    let client = AuthClient(configuration: adapter.configuration, service: adapter, storage: store)
    try await client.restoreSession()
    await #expect(throws: failure) { try await client.validAccessToken() }
    await #expect(throws: failure) { try await client.validAccessToken() }
    #expect(adapter.refreshCount == 1)
    #expect(try store.load()?.refreshToken == "original")
    let restored = AuthClient(
      configuration: adapter.configuration, service: adapter, storage: store)
    try await restored.restoreSession()
    await #expect(
      throws: failure == .refreshRejected ? AuthError.refreshRejected : .refreshOutcomeUnknown
    ) { try await restored.validAccessToken() }
    #expect(adapter.refreshCount == 1)
  }

  @Test func keychainUnavailableDoesNotMeanSignedOut() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    let store = MemoryStorage()
    store.fail(.keychain(status: -25308))
    let client = AuthClient(configuration: adapter.configuration, service: adapter, storage: store)
    await #expect(throws: AuthError.keychain(status: -25308)) { try await client.restoreSession() }
    #expect(await client.state == .restoring)
  }

  @Test func storageFailureAfterRotationQuarantinesOldDiskToken() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    let store = MemoryStorage()
    try store.save(.init(identity: adapter.identity, refreshToken: "original"))
    adapter.failStorageAfterRefresh = store
    let client = AuthClient(configuration: adapter.configuration, service: adapter, storage: store)
    try await client.restoreSession()
    await #expect(throws: AuthError.keychain(status: -25308)) {
      try await client.validAccessToken()
    }
    store.fail(nil)
    #expect(try store.load()?.refreshInFlight == true)
    #expect(try store.load()?.refreshToken == "original")
    let restored = AuthClient(
      configuration: adapter.configuration, service: adapter, storage: store)
    try await restored.restoreSession()
    await #expect(throws: AuthError.refreshOutcomeUnknown) { try await restored.validAccessToken() }
    #expect(adapter.refreshCount == 1)
  }

  @Test func logoutDuringLoginInvalidatesResult() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    let store = MemoryStorage()
    adapter.holdLogin = true
    let client = AuthClient(configuration: adapter.configuration, service: adapter, storage: store)
    let login = Task { try await client.login() }
    while adapter.heldLogin == nil { await Task.yield() }
    await #expect(throws: AuthError.loginAlreadyInProgress) { try await client.login() }
    try await client.logout()
    adapter.heldLogin?.resume(returning: adapter.tokens())
    await #expect(throws: AuthError.operationInvalidated) { try await login.value }
    #expect(await client.state == .signedOut())
    #expect(try store.load() == nil)
  }

  @Test func logoutDuringRefreshInvalidatesResult() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    let store = MemoryStorage()
    adapter.holdRefresh = true
    try store.save(.init(identity: adapter.identity, refreshToken: "original"))
    let client = AuthClient(configuration: adapter.configuration, service: adapter, storage: store)
    try await client.restoreSession()
    let refresh = Task { try await client.validAccessToken() }
    while adapter.heldRefresh == nil { await Task.yield() }
    try await client.logout()
    adapter.heldRefresh?.resume(returning: adapter.tokens())
    await #expect(throws: AuthError.operationInvalidated) { try await refresh.value }
    #expect(try store.load() == nil)
    #expect(await client.state == .signedOut())
  }

  @Test func cancellationDoesNotPublishLogin() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    let store = MemoryStorage()
    adapter.holdLogin = true
    let client = AuthClient(configuration: adapter.configuration, service: adapter, storage: store)
    let login = Task { try await client.login() }
    while adapter.heldLogin == nil { await Task.yield() }
    await client.cancelLogin()
    adapter.heldLogin?.resume(returning: adapter.tokens())
    await #expect(throws: AuthError.operationInvalidated) { try await login.value }
    #expect(try store.load() == nil)
  }

  @Test func failedLogoutBlocksRestorationUntilDeleteSucceeds() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    let store = MemoryStorage()
    let client = AuthClient(configuration: adapter.configuration, service: adapter, storage: store)
    try await client.login()
    store.fail(.keychain(status: -25308))
    await #expect(throws: AuthError.keychain(status: -25308)) { try await client.logout() }
    #expect(await client.state == .signedOut(problem: .keychain(status: -25308)))
    await #expect(throws: AuthError.storage) { try await client.restoreSession() }
    store.fail(nil)
    try await client.logout()
    #expect(try store.load() == nil)
  }

  @Test func isolatesNamespaceIssuerClientAndResource() throws {
    let a = try configuration()
    let alternatives = [
      try configuration(namespace: "com.example.two.production"),
      try configuration(namespace: "com.example.one.staging"),
      try configuration(issuer: "https://other.example.com/"),
      try configuration(clientID: "two"), try configuration(audience: "api-two"),
    ]
    #expect(alternatives.allSatisfy { $0.storageService != a.storageService })
    #expect(Set(alternatives.map(\.storageService)).count == alternatives.count)
  }
}
