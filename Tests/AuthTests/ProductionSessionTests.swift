import Darwin
import Foundation
import Testing

@testable import Auth

@Suite @MainActor struct ProductionSessionTests {
  @Test func failedPrerequisiteCanBeRetriedWithoutQuarantiningCredential() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    let store = MemoryStorage()
    try store.save(.init(identity: adapter.identity, refreshToken: "original"))
    let client = AuthClient(configuration: adapter.configuration, service: adapter, storage: store)
    try await client.restoreSession()
    adapter.prepareFailure = .discovery
    await #expect(throws: AuthError.discovery) { try await client.validAccessToken() }
    #expect(try store.load()?.refreshInFlight == false)
    #expect(adapter.refreshCount == 0)
    adapter.prepareFailure = nil
    #expect(try await client.validAccessToken() == "new-access-1")
  }

  @Test func preSendStorageFailureRemainsRetryable() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    let store = MemoryStorage()
    try store.save(.init(identity: adapter.identity, refreshToken: "original"))
    let client = AuthClient(configuration: adapter.configuration, service: adapter, storage: store)
    try await client.restoreSession()
    store.fail(.keychain(status: -25308))
    await #expect(throws: AuthError.keychain(status: -25308)) {
      try await client.validAccessToken()
    }
    #expect(adapter.refreshCount == 0)
    store.fail(nil)
    #expect(try await client.validAccessToken() == "new-access-1")
  }

  @Test func shortLivedTokenWithoutRefreshIsUsable() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    adapter.tokenLifetime = 30
    adapter.providesRefreshToken = false
    let client = AuthClient(
      configuration: adapter.configuration, service: adapter, storage: MemoryStorage())
    try await client.login()
    #expect(try await client.validAccessToken() == "synthetic-access")
    #expect(adapter.refreshCount == 0)
  }

  @Test func loginWaitsUntilPreviousBrowserCancellationFinishes() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    adapter.holdCancel = true
    let client = AuthClient(
      configuration: adapter.configuration, service: adapter, storage: MemoryStorage())
    let logout = Task { try await client.logout() }
    while adapter.heldCancel == nil { await Task.yield() }
    await #expect(throws: AuthError.loginAlreadyInProgress) { try await client.login() }
    adapter.heldCancel?.resume()
    try await logout.value
    adapter.holdCancel = false
    try await client.login()
    #expect(await client.state == .signedIn(adapter.identity))
  }

  @Test func failedLogoutSurvivesCoordinatorReplacement() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    let store = MemoryStorage()
    let client = AuthClient(configuration: adapter.configuration, service: adapter, storage: store)
    try await client.login()
    store.fail(.keychain(status: -25308))
    await #expect(throws: AuthError.keychain(status: -25308)) { try await client.logout() }
    let replacement = AuthClient(
      configuration: adapter.configuration, service: adapter, storage: store)
    await #expect(throws: AuthError.keychain(status: -25308)) {
      try await replacement.restoreSession()
    }
    await #expect(throws: AuthError.storage) { try await replacement.login() }
    store.fail(nil)
    try await replacement.restoreSession()
    #expect(await replacement.state == .signedOut())
    #expect(try store.load() == nil)
  }

  @Test func publicClientsRejectSharedRotatingSession() async throws {
    let adapter = FakeAdapter(
      configuration: try configuration(namespace: "test." + UUID().uuidString))
    var first: AuthClient? = try await AuthClient(adapter: adapter)
    #expect(first != nil)
    await #expect(throws: AuthError.sessionAlreadyInUse) { try await AuthClient(adapter: adapter) }
    first = nil
    let replacement = try await AuthClient(adapter: adapter)
    #expect(await replacement.state == .restoring)
  }

  @Test func fileLockPreventsAnIndependentCoordinator() throws {
    let key = "test." + UUID().uuidString
    let lease = try SessionLease.acquire(key)
    let path = try SessionFiles.directory().appendingPathComponent(key + ".lock").path
    let descriptor = open(path, O_RDWR)
    #expect(descriptor >= 0)
    defer { close(descriptor) }
    withExtendedLifetime(lease) {
      #expect(flock(descriptor, LOCK_EX | LOCK_NB) != 0)
    }
  }

  @Test func sessionLeaseRejectsDuplicateAndReleasesOnDeinit() throws {
    let key = "test." + UUID().uuidString
    var lease: SessionLease? = try SessionLease.acquire(key)
    #expect(lease != nil)
    #expect(throws: AuthError.sessionAlreadyInUse) { _ = try SessionLease.acquire(key) }
    lease = nil
    let replacement = try SessionLease.acquire(key)
    withExtendedLifetime(replacement) {}
  }
}
