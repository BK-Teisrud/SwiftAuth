import Foundation
import Networking
import Testing

@testable import Auth

private actor ProtectedAPI: HTTPTransport {
  private(set) var tokens: [String] = []
  func send(_ request: URLRequest, redirectPolicy: RedirectPolicy) async throws -> HTTPResponse {
    guard request.url?.host == "api-one.example.com" else { throw AuthError.invalidConfiguration }
    let bearer = request.value(forHTTPHeaderField: "Authorization") ?? ""
    tokens.append(bearer)
    return .init(
      data: Data("{}".utf8),
      metadata: .init(statusCode: tokens.count == 1 ? 401 : 200, url: request.url))
  }
}

private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Date
  init(_ value: Date) { self.value = value }
  func now() -> Date { lock.withLock { value } }
  func advance(_ duration: TimeInterval) {
    lock.withLock { value = value.addingTimeInterval(duration) }
  }
}

@Suite @MainActor struct NetworkingIntegrationTests {
  @Test func protectedRequestRecoversOnceWithAccessCredential() async throws {
    let config = try configuration()
    let adapter = FakeAdapter(configuration: try configuration())
    let store = MemoryStorage()
    let auth = AuthClient(configuration: config, service: adapter, storage: store)
    try await auth.login()
    let transport = ProtectedAPI()
    let api = HTTPClient(
      configuration: try ClientConfiguration(
        baseURL: URL(string: "https://api-one.example.com/")!, transport: transport,
        credentialProvider: AuthCredentialProvider(client: auth)))
    let response = try await api.execute(
      HTTPRequest(pathSegments: ["protected"], requiresAuthentication: true))
    #expect(response.statusCode == 200)
    #expect(await transport.tokens == ["Bearer synthetic-access", "Bearer new-access-1"])
    #expect(adapter.refreshCount == 1)
  }

  @Test func expiredAccessIsNotReturnedWhenRefreshFails() async throws {
    let adapter = FakeAdapter(configuration: try configuration())
    let store = MemoryStorage()
    let clock = TestClock(Date())
    let auth = AuthClient(
      configuration: adapter.configuration, service: adapter, storage: store, now: { clock.now() })
    try await auth.login()
    clock.advance(3600)
    adapter.refreshFailure = .refreshOutcomeUnknown
    let credentials = AuthCredentialProvider(client: auth)
    await #expect(throws: AuthError.refreshOutcomeUnknown) { try await credentials.bearerToken() }
    await #expect(throws: AuthError.refreshOutcomeUnknown) { try await credentials.bearerToken() }
    #expect(adapter.refreshCount == 1)
  }

  @Test func malformedOrInsecureConfigurationIsRejected() throws {
    #expect(throws: AuthError.invalidConfiguration) {
      try AuthConfiguration(
        issuer: URL(string: "http://issuer.example.com/")!, clientID: "one",
        redirectURI: URL(string: "com.example.one://callback")!,
        apiResource: .auth0Audience("api-one"), keychainNamespace: "one.production")
    }
    #expect(throws: AuthError.invalidConfiguration) {
      try AuthConfiguration(
        issuer: URL(string: "https://issuer.example.com/")!, clientID: "one",
        redirectURI: URL(string: "https://callback.example.com/?unexpected=query")!,
        apiResource: .auth0Audience("api-one"), keychainNamespace: "one.production")
    }
  }
}
