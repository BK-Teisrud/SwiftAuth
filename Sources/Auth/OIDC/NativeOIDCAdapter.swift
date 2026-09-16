import Foundation
import Networking

/// Authorization Code + PKCE using Apple frameworks and this package's protocol implementation.
/// RS256 is the sole allowed ID-token algorithm. Other algorithms fail closed.
@MainActor public final class NativeOIDCAdapter: AuthOIDCAdapter {
  /// Uforanderlig OIDC-konfigurasjon brukt til discovery, validering og ressursvalg.
  public let configuration: AuthConfiguration
  private let browser: any AuthBrowserSession
  private let service: OIDCService
  private let now: @Sendable () -> Date
  private var preparedRefreshMetadata: OIDCMetadata?
  private var operationID: UUID?
  private var logoutHint: String?
  private var sessionGeneration: UInt64 = 0
  private var identityNonce: (identity: AuthIdentity, nonce: String)?
  /// Oppretter Apple-basert Authorization Code + PKCE-adapter.
  ///
  /// Transporten er som standard `URLSessionTransport`; en egendefinert transport må bevare redirect- og størrelsesbegrensninger.
  /// `now` er klokkeinjeksjon for deterministiske tester, med `Date()` som standard. Se <doc:ProvidersAndExtensions>.
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

  /// Utfører discovery, PKCE S256, state/nonce, systemnettleser, kodeutveksling og RS256-validering.
  ///
  /// Metodevalget må oppgis. Parsing og signaturvalidering skjer i en egen service-aktør.
  /// - Returns: Sensitivt, verifisert tokenresultat.
  /// - Throws: Strukturerte discovery-, callback-, browser-, token- eller valideringsfeil.
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

  /// Avbryter nettleseren og ugyldiggjør sene resultater; tømmer adapterens nonce, logout-hint og forberedte metadata.
  public func cancelLogin() {
    operationID = nil
    logoutHint = nil
    identityNonce = nil
    preparedRefreshMetadata = nil
    sessionGeneration &+= 1
    browser.cancel()
  }

  /// Henter eller gjenbruker discovery før klienten markerer refresh-token som sendt. Sender ingen refresh-credential.
  public func prepareRefresh() async throws {
    preparedRefreshMetadata = try await service.discover()
  }

  /// Utfører én refresh-utveksling med opprinnelig identitet, nonce og ID-token-binding.
  ///
  /// `nonce` og `binding` har standard `nil` på denne konkrete metoden. Refresh-ID-token kan utelates av tjenesten; returnerte claims valideres.
  /// Klientkoordinatoren eier deling, totalfrist og vedvarende karantene. Ikke bruk direkte som erstatning for ``AuthClient``.
  /// - Returns: Verifisert sensitivt resultat; manglende nytt refresh-token betyr at det gamle beholdes.
  /// - Throws: Refresh-, nettverks-, protokoll-, signatur- eller kanselleringsfeil.
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

  /// Utfører leverandørutlogging via validert end-session-endepunkt og konfigurert logout-callback.
  ///
  /// Eventuelt verifisert ID-token-hint finnes bare i minnet; lokal klientlagring slettes ikke.
  /// - Throws: `unsupportedProviderFeature` eller browser-/callback-/discovery-feil.
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
