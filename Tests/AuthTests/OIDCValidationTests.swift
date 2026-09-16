import CryptoKit
import Foundation
import Networking
import Security
import Testing

@testable import Auth

private enum FixtureMode: String, CaseIterable, Sendable {
  case valid, issuer, audience, nonce, expired, signature, algorithm, azp
  case singleAzp, booleanExpiry, futureIssuedAt, futureNotBefore, accessHash, criticalHeader,
    unknownKey
  case callback, state, duplicateState, cancelled, providerDenied, discoveryIssuer, discoveryMissing
}

/// Synthetic signing is test-fixture construction only; production validation uses Apple Security.
private final class SignedFixture: @unchecked Sendable {
  let key: SecKey
  let modulus: Data
  let exponent: Data
  let mode: FixtureMode
  let keyID: String
  private var keyRequests = 0
  private let lock = NSLock()
  private var nonce = ""
  private var verifierMatches = false
  private var challenge = ""
  init(mode: FixtureMode, keyID: String = "synthetic-key") throws {
    self.mode = mode
    self.keyID = keyID
    var failure: Unmanaged<CFError>?
    guard
      let key = SecKeyCreateRandomKey(
        [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, &failure
      ),
      let publicKey = SecKeyCopyPublicKey(key),
      let external = SecKeyCopyExternalRepresentation(publicKey, &failure) as Data?
    else { throw AuthError.storage }
    self.key = key
    // DER PKCS#1 public key: SEQUENCE { INTEGER modulus, INTEGER exponent }.
    let bytes = Array(external)
    var offset = 0
    func readLength() throws -> Int {
      guard offset < bytes.count else { throw AuthError.storage }
      let first = Int(bytes[offset])
      offset += 1
      if first < 128 { return first }
      let count = first & 127
      guard count > 0, count <= 4, offset + count <= bytes.count else { throw AuthError.storage }
      var length = 0
      for _ in 0..<count {
        length = length * 256 + Int(bytes[offset])
        offset += 1
      }
      return length
    }
    guard bytes[offset] == 0x30 else { throw AuthError.storage }
    offset += 1
    _ = try readLength()
    func integer() throws -> Data {
      guard offset < bytes.count, bytes[offset] == 0x02 else { throw AuthError.storage }
      offset += 1
      let length = try readLength()
      guard offset + length <= bytes.count else { throw AuthError.storage }
      var value = Array(bytes[offset..<(offset + length)])
      offset += length
      while value.first == 0 { value.removeFirst() }
      return Data(value)
    }
    self.modulus = try integer()
    self.exponent = try integer()
  }
  static func base64(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(
      of: "/", with: "_"
    ).replacingOccurrences(of: "=", with: "")
  }
  func capture(nonce: String, challenge: String) {
    lock.withLock {
      self.nonce = nonce
      self.challenge = challenge
    }
  }
  var jwksRequestCount: Int { lock.withLock { keyRequests } }
  var validPKCE: Bool { lock.withLock { verifierMatches } }
  func token(
    audiences: [String]? = nil, authenticationTime: Double? = nil, includeNonce: Bool = true
  ) throws -> String {
    let nonce = lock.withLock { self.nonce }
    let time = Date().timeIntervalSince1970
    var claims: [String: Any] = [
      "iss": "https://issuer.example.com/", "sub": "synthetic-user", "aud": "one",
      "iat": time - 10, "exp": time + 600, "nonce": nonce,
    ]
    switch mode {
    case .issuer: claims["iss"] = "https://wrong.example.com/"
    case .audience: claims["aud"] = "wrong-client"
    case .nonce: claims["nonce"] = "wrong-nonce"
    case .expired: claims["exp"] = time - 120
    case .singleAzp: claims["azp"] = "wrong-client"
    case .booleanExpiry: claims["exp"] = true
    case .futureIssuedAt: claims["iat"] = time + 300
    case .futureNotBefore: claims["nbf"] = time + 300
    case .accessHash: claims["at_hash"] = "wrong-hash"
    case .azp:
      claims["aud"] = ["one", "second"]
      claims["azp"] = "wrong-client"
    default: break
    }
    if let audiences {
      claims["aud"] = audiences
      claims["azp"] = "one"
    }
    if let authenticationTime { claims["auth_time"] = authenticationTime }
    if !includeNonce { claims.removeValue(forKey: "nonce") }
    var headerFields: [String: Any] = [
      "alg": mode == .algorithm ? "none" : "RS256",
      "kid": mode == .unknownKey ? "unknown-key" : keyID,
    ]
    if mode == .criticalHeader { headerFields["crit"] = ["unsupported"] }
    let header = try JSONSerialization.data(withJSONObject: headerFields)
    let body = try JSONSerialization.data(withJSONObject: claims)
    let message = Self.base64(header) + "." + Self.base64(body)
    var error: Unmanaged<CFError>?
    guard
      let raw = SecKeyCreateSignature(
        key, .rsaSignatureMessagePKCS1v15SHA256, Data(message.utf8) as CFData, &error) as Data?
    else { throw AuthError.storage }
    var signature = raw
    if mode == .signature { signature[0] ^= 0xFF }
    return message + "." + Self.base64(signature)
  }
  func response(_ request: URLRequest) throws -> Data {
    if request.url?.path == "/.well-known/jwks.json" {
      lock.withLock { keyRequests += 1 }
      return try JSONSerialization.data(withJSONObject: [
        "keys": [
          [
            "kty": "RSA", "use": "sig", "alg": "RS256",
            "kid": keyID, "n": Self.base64(modulus), "e": Self.base64(exponent),
          ]
        ]
      ])
    }
    var requestBody = request.httpBody
    if requestBody == nil, let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(contentsOf: buffer.prefix(count))
      }
      requestBody = data
    }
    if let body = requestBody,
      let parameters = URLComponents(
        string: "https://fixture.example/?" + (String(data: body, encoding: .utf8) ?? ""))?
        .queryItems.map({ Dictionary(uniqueKeysWithValues: $0.map { ($0.name, $0.value ?? "") }) }),
      let verifier = parameters["code_verifier"]
    {
      let digest = Self.base64(Data(SHA256.hash(data: Data(verifier.utf8))))
      lock.withLock { verifierMatches = digest == challenge && !challenge.isEmpty }
    }
    return try JSONSerialization.data(withJSONObject: [
      "access_token": "synthetic-access", "token_type": "Bearer",
      "expires_in": 600, "refresh_token": "synthetic-refresh", "id_token": try token(),
    ])
  }
  var discovery: Data {
    get throws {
      if mode == .discoveryMissing { return Data("{}".utf8) }
      return try JSONSerialization.data(withJSONObject: [
        "issuer": mode == .discoveryIssuer
          ? "https://wrong.example.com/" : "https://issuer.example.com/",
        "authorization_endpoint": "https://issuer.example.com/authorize",
        "token_endpoint": "https://issuer.example.com/oauth/token",
        "jwks_uri": "https://issuer.example.com/.well-known/jwks.json",
        "response_types_supported": ["code"],
        "code_challenge_methods_supported": ["S256"],
        "id_token_signing_alg_values_supported": ["RS256"],
      ])
    }
  }
}

private struct DiscoveryTransport: HTTPTransport {
  let fixture: SignedFixture
  func send(_ request: URLRequest, redirectPolicy: RedirectPolicy) async throws -> HTTPResponse {
    .init(
      data: try request.url?.path == "/.well-known/openid-configuration"
        ? fixture.discovery : fixture.response(request),
      metadata: .init(statusCode: 200, url: request.url))
  }
}

@MainActor private final class FixtureBrowser: AuthBrowserSession {
  let fixture: SignedFixture
  private(set) var capturedURL: URL?
  init(_ fixture: SignedFixture) { self.fixture = fixture }
  func authenticate(url: URL, callbackURI: URL, ephemeral: Bool) async throws -> URL {
    capturedURL = url
    if fixture.mode == .cancelled { throw AuthError.cancelled }
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
    func value(_ name: String) -> String { items.first { $0.name == name }?.value ?? "" }
    guard !value("state").isEmpty, !value("nonce").isEmpty, !value("code_challenge").isEmpty,
      value("code_challenge_method") == "S256", value("response_type") == "code"
    else { throw AuthError.callback }
    fixture.capture(nonce: value("nonce"), challenge: value("code_challenge"))
    var callback = URLComponents(url: callbackURI, resolvingAgainstBaseURL: false)!
    if fixture.mode == .callback { callback.path = "/wrong" }
    callback.queryItems = [
      .init(name: "code", value: "synthetic-code"),
      .init(name: "state", value: fixture.mode == .state ? "wrong-state" : value("state")),
    ]
    if fixture.mode == .providerDenied {
      callback.queryItems?.removeAll { $0.name == "code" }
      callback.queryItems?.append(.init(name: "error", value: "access_denied"))
    }
    if fixture.mode == .duplicateState {
      callback.queryItems!.append(.init(name: "state", value: value("state")))
    }
    return callback.url!
  }
  func cancel() {}
}

@Suite(.serialized) @MainActor struct OIDCValidationTests {
  @Test func unknownKeyRefreshesJWKSAndVerifiesNewRSAKey() async throws {
    let first = try SignedFixture(mode: .valid, keyID: "first-key")
    let second = try SignedFixture(mode: .valid, keyID: "rotated-key")
    let transport = RotatingTransport(first: first, second: second)
    let config = try configuration()
    let adapter = NativeOIDCAdapter(
      configuration: config, browser: FixtureBrowser(first), transport: transport)
    let original = try await adapter.login(choice: .serviceSelection)
    second.capture(nonce: original.loginNonce!, challenge: "")
    await transport.rotate()
    let refreshed = try await adapter.refresh(
      token: "synthetic-refresh", identity: original.identity,
      nonce: original.loginNonce, binding: original.idTokenBinding)
    #expect(refreshed.identity == original.identity)
    #expect(first.jwksRequestCount == 1)
    #expect(second.jwksRequestCount == 1)
    _ = try await adapter.refresh(
      token: "synthetic-refresh", identity: original.identity,
      nonce: original.loginNonce, binding: original.idTokenBinding)
    #expect(second.jwksRequestCount == 1)
  }

  @Test func additionalAudienceRequiresExplicitTrust() throws {
    let fixture = try SignedFixture(mode: .valid)
    let jwks = try fixture.response(
      URLRequest(url: URL(string: "https://issuer.example.com/.well-known/jwks.json")!))
    let token = try fixture.token(audiences: ["one", "second"])
    #expect(throws: AuthError.idTokenValidation) {
      try IDTokenValidator(configuration: configuration(), now: { Date() }).validate(
        token, jwks: jwks, nonce: nil)
    }
    let trustedConfiguration = try configuration(trustedAudiences: ["second"])
    let identity = try IDTokenValidator(configuration: trustedConfiguration, now: { Date() })
      .validate(
        token, jwks: jwks, nonce: nil)
    #expect(identity.subject == "synthetic-user")
  }

  @Test func nativeRefreshKeepsOriginalBindingAcrossAdapterReplacement() async throws {
    let fixture = try SignedFixture(mode: .valid)
    let config = try configuration()
    let transport = DiscoveryTransport(fixture: fixture)
    let first = NativeOIDCAdapter(
      configuration: config, browser: FixtureBrowser(fixture), transport: transport)
    let original = try await first.login(choice: .serviceSelection)
    #expect(original.idTokenBinding?.audiences == ["one"])
    let restored = NativeOIDCAdapter(
      configuration: config, browser: FixtureBrowser(fixture), transport: transport)
    let refreshed = try await restored.refresh(
      token: "synthetic-refresh", identity: original.identity,
      nonce: original.loginNonce, binding: original.idTokenBinding)
    #expect(refreshed.identity == original.identity)
    #expect(fixture.jwksRequestCount == 2)
    await #expect(throws: AuthError.idTokenValidation) {
      try await restored.refresh(
        token: "synthetic-refresh", identity: original.identity,
        nonce: "wrong-nonce", binding: original.idTokenBinding)
    }
  }

  @Test func refreshRejectsChangedOriginalAudienceAndAuthenticationTime() async throws {
    let fixture = try SignedFixture(mode: .valid)
    let config = try configuration(trustedAudiences: ["second"])
    let jwks = try fixture.response(
      URLRequest(url: URL(string: "https://issuer.example.com/.well-known/jwks.json")!))
    let validator = IDTokenValidator(configuration: config, now: { Date() })
    let identity = AuthIdentity(issuer: config.issuer.absoluteString, subject: "synthetic-user")
    let original = AuthIDTokenBinding(audiences: ["one"], authenticationTime: 100)
    #expect(throws: AuthError.idTokenValidation) {
      try validator.validate(
        fixture.token(audiences: ["one", "second"], authenticationTime: 100),
        jwks: jwks, nonce: nil, identity: identity, binding: original)
    }
    #expect(throws: AuthError.idTokenValidation) {
      try validator.validate(
        fixture.token(authenticationTime: 200), jwks: jwks, nonce: nil,
        identity: identity, binding: original)
    }
    #expect(
      try validator.validate(
        fixture.token(authenticationTime: 100), jwks: jwks, nonce: nil,
        identity: identity, binding: original) == identity)
  }

  @Test(arguments: FixtureMode.allCases) private func appleSecurityValidatesSignedTokens(
    _ mode: FixtureMode
  ) async throws {
    let fixture = try SignedFixture(mode: mode)
    let browser = FixtureBrowser(fixture)
    let config = try configuration()
    let adapter = NativeOIDCAdapter(
      configuration: config, browser: browser, transport: DiscoveryTransport(fixture: fixture))
    let store = MemoryStorage()
    let client = AuthClient(configuration: config, service: adapter, storage: store)
    if mode == .valid {
      try await client.login()
      #expect(try await client.validAccessToken() == "synthetic-access")
      #expect(
        await client.state
          == .signedIn(.init(issuer: config.issuer.absoluteString, subject: "synthetic-user")))
      #expect(fixture.validPKCE)
    } else {
      await #expect(throws: AuthError.self) { try await client.login() }
      #expect(try store.load() == nil)
      if [
        .issuer, .audience, .nonce, .expired, .signature, .algorithm, .azp, .singleAzp,
        .booleanExpiry, .futureIssuedAt, .futureNotBefore, .accessHash, .criticalHeader,
        .unknownKey,
      ].contains(mode) {
        #expect(await client.state == .signedOut(problem: .idTokenValidation))
      }
      if mode == .providerDenied {
        #expect(await client.state == .signedOut(problem: .providerRejected))
      }
      if mode == .cancelled { #expect(await client.state == .signedOut(problem: .cancelled)) }
      if [.discoveryIssuer, .discoveryMissing].contains(mode) {
        #expect(browser.capturedURL == nil)
      }
    }
  }
}

@Suite("OIDC JSON safety")
struct JSONSafetyTests {
  @Test(arguments: [
    #"{"alg":"RS256","alg":"none"}"#, #"{"alg":"RS256","\u0061lg":"none"}"#,
    #"{"keys":[{"kid":"a","kid":"b"}]}"#,
  ])
  func rejectsDuplicateKeys(_ json: String) {
    #expect(throws: AuthError.idTokenValidation) { try StrictJSON.object(Data(json.utf8)) }
  }
  @Test func acceptsDistinctKeysInSeparateObjects() throws {
    let object = try StrictJSON.object(Data(#"{"keys":[{"kid":"a"},{"kid":"b"}]}"#.utf8))
    #expect((object["keys"] as? [[String: String]])?.count == 2)
  }
}

private actor RotatingTransport: HTTPTransport {
  let first: SignedFixture
  let second: SignedFixture
  var rotated = false
  init(first: SignedFixture, second: SignedFixture) {
    self.first = first
    self.second = second
  }
  func rotate() { rotated = true }
  func send(_ request: URLRequest, redirectPolicy: RedirectPolicy) async throws -> HTTPResponse {
    let fixture = rotated ? second : first
    let data =
      try request.url?.path == "/.well-known/openid-configuration"
      ? fixture.discovery : fixture.response(request)
    return .init(data: data, metadata: .init(statusCode: 200, url: request.url))
  }
}

private enum NativeResponseMode: CaseIterable, Sendable {
  case noIDToken, noNonce, badExpiry, badTokenType, emptyRefresh, malformedJSON, invalidGrant,
    lostResponse
}
private struct RefreshResponseTransport: HTTPTransport {
  let fixture: SignedFixture
  let mode: NativeResponseMode
  func send(_ request: URLRequest, redirectPolicy: RedirectPolicy) async throws -> HTTPResponse {
    if request.url?.path == "/.well-known/openid-configuration" {
      return .init(data: try fixture.discovery, metadata: .init(statusCode: 200, url: request.url))
    }
    if request.url?.path == "/.well-known/jwks.json" {
      return .init(
        data: try fixture.response(request), metadata: .init(statusCode: 200, url: request.url))
    }
    switch mode {
    case .lostResponse: throw URLError(.networkConnectionLost)
    case .invalidGrant:
      return .init(
        data: Data(#"{"error":"invalid_grant"}"#.utf8),
        metadata: .init(statusCode: 400, url: request.url))
    case .malformedJSON:
      return .init(data: Data("{".utf8), metadata: .init(statusCode: 200, url: request.url))
    default: break
    }
    var fields = try StrictJSON.object(fixture.response(request))
    switch mode {
    case .noIDToken: fields.removeValue(forKey: "id_token")
    case .noNonce: fields["id_token"] = try fixture.token(includeNonce: false)
    case .badExpiry: fields["expires_in"] = true
    case .badTokenType: fields["token_type"] = "MAC"
    case .emptyRefresh: fields["refresh_token"] = ""
    default: break
    }
    return .init(
      data: try JSONSerialization.data(withJSONObject: fields),
      metadata: .init(statusCode: 200, url: request.url))
  }
}

extension OIDCValidationTests {
  @Test(arguments: NativeResponseMode.allCases)
  private func actualNativeRefreshHandlesProtocolResponses(_ mode: NativeResponseMode) async throws
  {
    let fixture = try SignedFixture(mode: .valid)
    let config = try configuration()
    let login = NativeOIDCAdapter(
      configuration: config, browser: FixtureBrowser(fixture),
      transport: DiscoveryTransport(fixture: fixture))
    let original = try await login.login(choice: .serviceSelection)
    let adapter = NativeOIDCAdapter(
      configuration: config, browser: FixtureBrowser(fixture),
      transport: RefreshResponseTransport(fixture: fixture, mode: mode))
    if mode == .noIDToken || mode == .noNonce {
      let result = try await adapter.refresh(
        token: "old", identity: original.identity, nonce: original.loginNonce,
        binding: original.idTokenBinding)
      #expect(result.identity == original.identity)
      #expect(result.idTokenBinding == original.idTokenBinding)
    } else {
      let expected: AuthError =
        mode == .invalidGrant
        ? .refreshRejected
        : (mode == .lostResponse || mode == .malformedJSON)
          ? .refreshOutcomeUnknown : .tokenExchange
      await #expect(throws: expected) {
        try await adapter.refresh(
          token: "old", identity: original.identity, nonce: original.loginNonce,
          binding: original.idTokenBinding)
      }
    }
  }

  @Test(arguments: ["private", "duplicate", "weak", "exponent", "use", "operations", "encoding"])
  func invalidJWKVariantsAreRejected(_ variant: String) throws {
    let fixture = try SignedFixture(mode: .valid)
    var key: [String: Any] = [
      "kty": "RSA", "kid": fixture.keyID, "n": SignedFixture.base64(fixture.modulus),
      "e": SignedFixture.base64(fixture.exponent),
    ]
    switch variant {
    case "private": key["d"] = "private-material"
    case "weak": key["n"] = SignedFixture.base64(Data(fixture.modulus.suffix(128)))
    case "exponent": key["e"] = SignedFixture.base64(Data([2]))
    case "use": key["use"] = "enc"
    case "operations": key["key_ops"] = ["encrypt"]
    case "encoding": key["n"] = SignedFixture.base64(fixture.modulus) + "="
    default: break
    }
    let keys = variant == "duplicate" ? [key, key] : [key]
    let jwks = try JSONSerialization.data(withJSONObject: ["keys": keys])
    #expect(throws: AuthError.idTokenValidation) {
      try IDTokenValidator(configuration: configuration(), now: { Date() }).validate(
        fixture.token(), jwks: jwks, nonce: nil)
    }
  }

  @Test func endpointTrustAndStaticQueriesAreEnforced() async throws {
    let fixture = try SignedFixture(mode: .valid)
    let config = try configuration()
    var metadata = try StrictJSON.object(fixture.discovery)
    metadata["authorization_endpoint"] = "https://other.example.com/authorize?tenant=one"
    let untrusted = OIDCService(
      configuration: config,
      transport: StaticDiscovery(data: try JSONSerialization.data(withJSONObject: metadata)),
      now: { Date() })
    await #expect(throws: AuthError.discovery) { try await untrusted.discover() }
    let trustedConfig = try AuthConfiguration(
      issuer: config.issuer, clientID: config.clientID, redirectURI: config.redirectURI,
      apiResource: config.apiResource, keychainNamespace: config.keychainNamespace,
      trustedEndpointOrigins: [URL(string: "https://other.example.com")!])
    let trusted = OIDCService(
      configuration: trustedConfig,
      transport: StaticDiscovery(data: try JSONSerialization.data(withJSONObject: metadata)),
      now: { Date() })
    #expect(try await trusted.discover().authorizationEndpoint.query == "tenant=one")
    metadata["authorization_endpoint"] = "https://other.example.com/authorize?state=override"
    let conflict = OIDCService(
      configuration: trustedConfig,
      transport: StaticDiscovery(data: try JSONSerialization.data(withJSONObject: metadata)),
      now: { Date() })
    await #expect(throws: AuthError.discovery) { try await conflict.discover() }
  }
}
private struct StaticDiscovery: HTTPTransport {
  let data: Data
  func send(_ request: URLRequest, redirectPolicy: RedirectPolicy) async throws -> HTTPResponse {
    .init(data: data, metadata: .init(statusCode: 200, url: request.url))
  }
}

private struct FailingURLTransport: HTTPTransport {
  func send(_ request: URLRequest, redirectPolicy: RedirectPolicy) async throws -> HTTPResponse {
    throw URLError(.notConnectedToInternet)
  }
}
extension OIDCValidationTests {
  @Test func rawURLSessionErrorsUseSafeRetryableErrorsBeforeCredentialSend() async throws {
    let config = try configuration()
    let service = OIDCService(
      configuration: config, transport: FailingURLTransport(), now: { Date() })
    await #expect(throws: AuthError.networkUnavailable) { try await service.discover() }
    await #expect(throws: AuthError.networkUnavailable) {
      try await service.token(
        URL(string: "https://issuer.example.com/token")!, fields: [], refresh: false)
    }
    await #expect(throws: AuthError.refreshOutcomeUnknown) {
      try await service.token(
        URL(string: "https://issuer.example.com/token")!, fields: [], refresh: true)
    }
  }
}
