import AuthenticationServices
import Foundation

/// Providers supported without an external identity broker.
public enum DirectAuthProvider: String, Sendable, Codable {
  /// Native Sign in with Apple, verified by your backend.
  case apple
  /// GitHub OAuth authorization with S256 PKCE, exchanged by your backend.
  case github
}

/// A short-lived, single-use transaction issued by your backend before provider authorization.
/// The backend must bind the transaction to provider, application, state, nonce and PKCE challenge.
public struct DirectAuthTransaction: Sendable, CustomStringConvertible, CustomDebugStringConvertible
{
  /// Sensitive opaque transaction identifier. Never log or persist provider evidence.
  public let id: String
  /// Creates a transaction from a validated backend response.
  public init(id: String) { self.id = id }
  /// Redacted description containing no credentials.
  public var description: String { "DirectAuthTransaction(<REDACTED>)" }
  /// Redacted debug description containing no credentials.
  public var debugDescription: String { description }
}

/// Unverified provider evidence. Only the backend may turn this into an application session.
public struct DirectAuthProof: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  /// Provider whose authorization evidence the backend must verify.
  public let provider: DirectAuthProvider
  /// Sensitive single-use identifier binding this evidence to the original transaction.
  public let transactionID: String
  /// Sensitive authorization code for server-side exchange.
  public let authorizationCode: String
  /// Unverified Apple identity token; nil for GitHub. Never use it directly as an app identity.
  public let identityToken: String?
  /// Sensitive GitHub PKCE verifier; nil for Apple.
  public let codeVerifier: String?
  /// Redacted description containing no credentials.
  public var description: String { "DirectAuthProof(<REDACTED>)" }
  /// Redacted debug description containing no credentials.
  public var debugDescription: String { description }
}

/// Implement with your application's HTTPS API client. No endpoint paths or wire format are assumed.
/// Never log credentials, follow redirects with credentials, or automatically retry exchange/refresh.
public protocol DirectAuthBackend: Sendable {
  /// Registers a short-lived transaction. Nonce is sent unchanged to Apple; challenge uses S256 for GitHub.
  func begin(
    provider: DirectAuthProvider, state: String, nonce: String?, codeChallenge: String?,
    redirectURI: URL
  ) async throws -> DirectAuthTransaction
  /// Exchanges single-use evidence after server-side provider verification and returns your own session.
  /// Identity issuer must equal the configured backend URL; subject must be your stable internal user ID.
  func exchange(_ proof: DirectAuthProof) async throws -> AuthTokenResponse
  /// Rotates the application's refresh token exactly once, preserving the internal user identity.
  func refresh(token: String, identity: AuthIdentity) async throws -> AuthTokenResponse
}

/// Native Apple authorization boundary. The returned credential remains unverified until backend exchange.
@MainActor public protocol DirectAppleAuthorization: Sendable {
  /// Uses the exact nonce/state on the Apple request and cooperates with cancellation.
  func authorize(nonce: String, state: String) async throws -> ASAuthorizationAppleIDCredential
  /// Cancels pending native authorization and rejects late results.
  func cancel()
}

/// Direct Apple/GitHub login followed by session issuance by your own backend.
/// Construct AuthClient with this adapter; existing storage, refresh quarantine and API integration apply.
@MainActor public final class DirectAuthAdapter: AuthOIDCAdapter {
  /// Immutable application-session and storage configuration; no OIDC discovery is used.
  public let configuration: AuthConfiguration
  private let backend: any DirectAuthBackend
  private let apple: any DirectAppleAuthorization
  private let browser: any AuthBrowserSession
  private let githubClientID: String
  private var operation: UUID?

  /// Backend URL is an identity namespace, not an OIDC discovery endpoint. No discovery is performed.
  /// The callback and GitHub client ID must match provider registration. No client secrets belong here.
  public init(
    backendURL: URL, applicationID: String, githubClientID: String,
    redirectURI: URL, keychainNamespace: String, backend: any DirectAuthBackend,
    apple: any DirectAppleAuthorization, browser: any AuthBrowserSession,
    ephemeralBrowserSession: Bool = false, refreshTimeout: TimeInterval = 60
  ) throws {
    guard !githubClientID.isEmpty else { throw AuthError.invalidConfiguration }
    configuration = try AuthConfiguration(
      issuer: backendURL, clientID: applicationID,
      redirectURI: redirectURI, apiResource: .oauthResource(backendURL),
      keychainNamespace: keychainNamespace,
      loginChoices: [.connection("apple"), .connection("github")],
      ephemeralBrowserSession: ephemeralBrowserSession, refreshTimeout: refreshTimeout)
    self.backend = backend
    self.apple = apple
    self.browser = browser
    self.githubClientID = githubClientID
  }

  /// Use `.connection("apple")` or `.connection("github")` explicitly.
  public func login(choice: AuthLoginChoice) async throws -> AuthTokenResponse {
    guard case .connection(let name) = choice, let provider = DirectAuthProvider(rawValue: name)
    else { throw AuthError.unsupportedProviderFeature }
    guard operation == nil else { throw AuthError.loginAlreadyInProgress }
    let id = UUID()
    operation = id
    defer { if operation == id { operation = nil } }
    let state = try OIDCEncoding.random()
    let nonce = provider == .apple ? try OIDCEncoding.random() : nil
    let verifier = provider == .github ? try OIDCEncoding.random() : nil
    let challenge = verifier.map { OIDCEncoding.base64(OIDCEncoding.sha256(Data($0.utf8))) }
    let transaction = try await backend.begin(
      provider: provider, state: state, nonce: nonce,
      codeChallenge: challenge, redirectURI: configuration.redirectURI)
    try check(id)
    guard !transaction.id.isEmpty else { throw AuthError.tokenExchange }
    let proof: DirectAuthProof
    switch provider {
    case .apple:
      let credential = try await apple.authorize(nonce: nonce!, state: state)
      try check(id)
      guard credential.state == state,
        let data = credential.authorizationCode, let code = String(data: data, encoding: .utf8),
        !code.isEmpty, let tokenData = credential.identityToken,
        let token = String(data: tokenData, encoding: .utf8), !token.isEmpty
      else { throw AuthError.callback }
      proof = DirectAuthProof(
        provider: .apple, transactionID: transaction.id,
        authorizationCode: code, identityToken: token, codeVerifier: nil)
    case .github:
      var url = URLComponents(string: "https://github.com/login/oauth/authorize")!
      url.queryItems = [
        .init(name: "client_id", value: githubClientID),
        .init(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
        .init(name: "state", value: state), .init(name: "code_challenge", value: challenge),
        .init(name: "code_challenge_method", value: "S256"),
      ]
      let callback = try await browser.authenticate(
        url: url.url!,
        callbackURI: configuration.redirectURI, ephemeral: configuration.ephemeralBrowserSession)
      try check(id)
      let fields = try OIDCCallbackValidator(issuer: URL(string: "https://github.com")!).fields(
        callback, expected: configuration.redirectURI, state: state)
      if fields["error"] != nil { throw AuthError.providerRejected }
      guard let code = fields["code"], !code.isEmpty else { throw AuthError.callback }
      proof = DirectAuthProof(
        provider: .github, transactionID: transaction.id,
        authorizationCode: code, identityToken: nil, codeVerifier: verifier)
    }
    let response = try await backend.exchange(proof)
    try check(id)
    try validate(response)
    return response
  }

  /// Invalidates the current transaction locally and cancels native/browser presentation.
  public func cancelLogin() async {
    operation = nil
    apple.cancel()
    browser.cancel()
  }

  /// Rotates a backend refresh token once and rejects identity changes or missing replacement tokens.
  public func refresh(
    token: String, identity: AuthIdentity, nonce: String?,
    binding: AuthIDTokenBinding?
  ) async throws -> AuthTokenResponse {
    let response = try await backend.refresh(token: token, identity: identity)
    try Task.checkCancellation()
    try validate(response)
    guard response.identity == identity, let replacement = response.refreshToken,
      !replacement.isEmpty
    else { throw AuthError.refreshRejected }
    return response
  }

  /// Provider logout is not application-session revocation. Revoke through your backend, then log out locally.
  public func logoutAtProvider() async throws { throw AuthError.unsupportedProviderFeature }

  private func check(_ id: UUID) throws {
    try Task.checkCancellation()
    guard operation == id else { throw AuthError.operationInvalidated }
  }

  private func validate(_ response: AuthTokenResponse) throws {
    guard response.identity.issuer == configuration.issuer.absoluteString,
      !response.identity.subject.isEmpty, !response.accessToken.isEmpty,
      response.expiresAt > Date(), response.refreshToken?.isEmpty != true,
      response.loginNonce == nil, response.idTokenBinding == nil
    else { throw AuthError.tokenExchange }
  }
}
