import Foundation
import Networking

/// Authorization Code + PKCE using Apple frameworks and this package's protocol implementation.
/// RS256 is the sole allowed ID-token algorithm. Other algorithms fail closed.
@MainActor public final class NativeOIDCAdapter: AuthOIDCAdapter {
  /// Immutable OIDC configuration used for discovery, validation, and resource selection.
  public let configuration: AuthConfiguration
  private let browser: any AuthBrowserSession
  private let service: OIDCService
  private let now: @Sendable () -> Date
  private var preparedRefreshMetadata: OIDCMetadata?
  private var operationID: UUID?
  private var logoutHint: String?
  private var sessionGeneration: UInt64 = 0
  private var identityNonce: (identity: AuthIdentity, nonce: String)?
  /// Creates an Apple-framework Authorization Code with PKCE adapter.
  ///
  /// Transport defaults to `URLSessionTransport`; a custom transport must preserve redirect and size limits.
  /// `now` injects a clock for deterministic tests and defaults to `Date()`. See <doc:ProvidersAndExtensions>.
  public init(
    configuration: AuthConfiguration, browser: any AuthBrowserSession,
    transport: any HTTPTransport = URLSessionTransport(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.configuration = configuration
    self.browser = browser
    self.service = OIDCService(configuration: configuration, transport: transport, now: now)
    self.now = now
  }

  /// Performs discovery, PKCE S256, state and nonce, system-browser presentation, code exchange, and RS256 validation.
  ///
  /// A login choice is required. Parsing and signature validation run in a separate service actor.
  /// - Returns: Sensitive, verified token output.
  /// - Throws: Structured discovery, callback, browser, token, or validation errors.
  public func login(choice: AuthLoginChoice) async throws -> AuthTokenResponse {
    guard operationID == nil else { throw AuthError.loginAlreadyInProgress }
    guard configuration.loginChoices.contains(choice) else {
      throw AuthError.unsupportedProviderFeature
    }
    let id = UUID()
    sessionGeneration &+= 1
    operationID = id
    defer { if operationID == id { operationID = nil } }
    let discovery = try await service.discover()
    try active(id)
    let verifier = try OIDCEncoding.random()
    let state = try OIDCEncoding.random()
    let nonce = try OIDCEncoding.random()
    var fields = [
      URLQueryItem(name: "response_type", value: "code"),
      .init(name: "client_id", value: configuration.clientID),
      .init(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
      .init(name: "scope", value: configuration.scopes.joined(separator: " ")),
      .init(name: "state", value: state), .init(name: "nonce", value: nonce),
      .init(name: "code_challenge_method", value: "S256"),
      .init(
        name: "code_challenge", value: OIDCEncoding.base64(OIDCEncoding.sha256(Data(verifier.utf8)))
      ),
    ]
    fields += resourceFields()
    if case .connection(let name) = choice { fields.append(.init(name: "connection", value: name)) }
    var url = URLComponents(url: discovery.authorizationEndpoint, resolvingAgainstBaseURL: false)!
    url.queryItems = (url.queryItems ?? []) + fields
    let callback: URL
    do {
      callback = try await browser.authenticate(
        url: url.url!, callbackURI: configuration.redirectURI,
        ephemeral: configuration.ephemeralBrowserSession)
    } catch {
      throw error is CancellationError
        ? AuthError.cancelled : error as? AuthError ?? .browserPresentation
    }
    try active(id)
    let items = try OIDCCallbackValidator(issuer: configuration.issuer).fields(
      callback, expected: configuration.redirectURI, state: state)
    if let error = items["error"] {
      throw error.isEmpty ? AuthError.callback : .providerRejected
    }
    guard let code = items["code"], !code.isEmpty else {
      throw AuthError.callback
    }
    let responseStarted = now()
    let response = try await service.token(
      discovery.tokenEndpoint,
      fields: [
        .init(name: "grant_type", value: "authorization_code"),
        .init(name: "client_id", value: configuration.clientID), .init(name: "code", value: code),
        .init(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
        .init(name: "code_verifier", value: verifier),
      ], refresh: false)
    try active(id)
    let result = try await service.validated(
      response, discovery: discovery, nonce: nonce, identity: nil, responseStarted: responseStarted)
    try active(id)
    logoutHint = response.idToken
    identityNonce = (result.identity, nonce)
    return result
  }

  /// Cancels browser work and invalidates late results, clearing adapter nonce, logout hint, and prepared metadata.
  public func cancelLogin() {
    operationID = nil
    logoutHint = nil
    identityNonce = nil
    preparedRefreshMetadata = nil
    sessionGeneration &+= 1
    browser.cancel()
  }

  /// Fetches or reuses discovery before the client marks the refresh token as sent. Sends no refresh credential.
  public func prepareRefresh() async throws {
    preparedRefreshMetadata = try await service.discover()
  }

  /// Performs one refresh exchange with the original identity, nonce, and ID-token binding.
  ///
  /// `nonce` and `binding` default to `nil` on this concrete method. The service may omit a refresh ID token; returned claims are validated.
  /// The client coordinator owns sharing, the total deadline, and durable quarantine. Do not use this as a substitute for ``AuthClient``.
  /// - Returns: Verified sensitive output; a missing replacement refresh token preserves the old token.
  /// - Throws: Refresh, network, protocol, signature, or cancellation errors.
  public func refresh(
    token refreshToken: String, identity: AuthIdentity, nonce originalNonce: String? = nil,
    binding: AuthIDTokenBinding? = nil
  ) async throws
    -> AuthTokenResponse
  {
    let epoch = sessionGeneration
    try Task.checkCancellation()
    let discovery: OIDCMetadata
    if let prepared = preparedRefreshMetadata {
      discovery = prepared
    } else {
      discovery = try await service.discover()
    }
    preparedRefreshMetadata = nil
    try Task.checkCancellation()
    guard epoch == sessionGeneration else { throw AuthError.operationInvalidated }
    let responseStarted = now()
    let response = try await service.token(
      discovery.tokenEndpoint,
      fields: [
        .init(name: "grant_type", value: "refresh_token"),
        .init(name: "client_id", value: configuration.clientID),
        .init(name: "refresh_token", value: refreshToken),
      ] + resourceFields(), refresh: true)
    try Task.checkCancellation()
    // Optional refresh nonce is checked only inside signature/claim validation.
    let nonce = originalNonce ?? (identityNonce?.identity == identity ? identityNonce?.nonce : nil)
    let result = try await service.validated(
      response, discovery: discovery, nonce: nonce, identity: identity,
      responseStarted: responseStarted, binding: binding)
    try Task.checkCancellation()
    guard epoch == sessionGeneration else { throw AuthError.operationInvalidated }
    logoutHint = response.idToken ?? logoutHint
    return result
  }

  /// Performs provider logout through a validated end-session endpoint and configured logout callback.
  ///
  /// An optional verified ID-token hint exists only in memory; local client storage is not deleted.
  /// - Throws: `unsupportedProviderFeature` or browser, callback, or discovery errors.
  public func logoutAtProvider() async throws {
    guard operationID == nil else { throw AuthError.loginAlreadyInProgress }
    guard let redirect = configuration.postLogoutRedirectURI else {
      throw AuthError.unsupportedProviderFeature
    }
    let id = UUID()
    operationID = id
    defer { if operationID == id { operationID = nil } }
    let discovery = try await service.discover()
    try active(id)
    guard let endpoint = discovery.endSessionEndpoint else {
      throw AuthError.unsupportedProviderFeature
    }
    let state = try OIDCEncoding.random()
    var url = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
    url.queryItems =
      (url.queryItems ?? []) + [
        .init(name: "client_id", value: configuration.clientID),
        .init(
          name: "post_logout_redirect_uri",
          value: redirect.absoluteString),
        .init(name: "state", value: state),
      ]
    if let logoutHint { url.queryItems?.append(.init(name: "id_token_hint", value: logoutHint)) }
    let callback = try await browser.authenticate(
      url: url.url!, callbackURI: redirect, ephemeral: configuration.ephemeralBrowserSession)
    try active(id)
    let items = try OIDCCallbackValidator(issuer: configuration.issuer).fields(
      callback, expected: redirect, state: state)
    if let error = items["error"] { throw error.isEmpty ? AuthError.callback : .providerRejected }
  }

  private func active(_ id: UUID) throws {
    try Task.checkCancellation()
    guard operationID == id else { throw AuthError.operationInvalidated }
  }
  private func resourceFields() -> [URLQueryItem] {
    switch configuration.apiResource {
    case .auth0Audience(let value): return [.init(name: "audience", value: value)]
    case .oauthResource(let value): return [.init(name: "resource", value: value.absoluteString)]
    }
  }

}
