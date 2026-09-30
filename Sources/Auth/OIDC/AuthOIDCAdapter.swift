import Foundation

/// Verified claims that must remain bound to the original authentication across refresh and restart.
public struct AuthIDTokenBinding: Codable, Sendable, Equatable {
  /// Sorted verified ID-token audiences preserved across refresh and restart.
  public let audiences: [String]
  /// The originally verified `auth_time` in seconds since the epoch, when the claim was present.
  public let authenticationTime: Double?
  /// Creates a binding and sorts audiences. Performs no cryptographic validation.
  public init(audiences: [String], authenticationTime: Double? = nil) {
    self.audiences = audiences.sorted()
    self.authenticationTime = authenticationTime
  }
}

/// Sensitive adapter output, never exposed by AuthState. Only return credentials after complete OIDC validation.
public struct AuthTokenResponse: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  /// Identity from a fully verified ID token or preserved refresh identity.
  public let identity: AuthIdentity
  /// Sensitive bearer token for the configured API; never log this value.
  public let accessToken: String
  /// Absolute expiry calculated from response lifetime. The client requires a future date.
  public let expiresAt: Date
  /// Sensitive refresh token. On refresh, `nil` preserves the existing token; on login, it means no refresh is stored.
  public let refreshToken: String?
  /// Original random OIDC nonce persisted for later refresh ID-token validation.
  public let loginNonce: String?
  /// Verified audiences and authentication time bound across refresh and restart.
  public let idTokenBinding: AuthIDTokenBinding?
  /// Creates sensitive adapter output. Validate protocol, signature, and claims before construction.
  ///
  /// Pass `refreshToken` explicitly, including `nil`. Nonce and binding default to `nil`; the native adapter supplies them after verified login.
  public init(
    identity: AuthIdentity, accessToken: String, expiresAt: Date, refreshToken: String?,
    loginNonce: String? = nil, idTokenBinding: AuthIDTokenBinding? = nil
  ) {
    self.identity = identity
    self.accessToken = accessToken
    self.expiresAt = expiresAt
    self.refreshToken = refreshToken
    self.loginNonce = loginNonce
    self.idTokenBinding = idTokenBinding
  }
  /// A redacted description that never includes identity or credentials.
  public var description: String { "AuthTokenResponse(<REDACTED>)" }
  /// The same redacted value as ``description``; never contains tokens.
  public var debugDescription: String { description }
}

/// Provider boundary. New adapters must validate discovery, PKCE, state, nonce, signature and OIDC claims. Use Apple cryptographic APIs.
/// Never return decoded-but-unverified ID-token identity. Never automatically retry rotating refresh requests.
@MainActor public protocol AuthOIDCAdapter: Sendable {
  /// Immutable client configuration that also determines the session's storage identity.
  var configuration: AuthConfiguration { get }
  /// Performs explicit login and returns only fully verified output. The protocol has no default login choice.
  func login(choice: AuthLoginChoice) async throws -> AuthTokenResponse
  /// Cancels browser work and invalidates late results without deleting the client's local session.
  func cancelLogin() async
  /// Prepares work such as discovery without sending the refresh token. Failures here may be retried without rotation quarantine.
  func prepareRefresh() async throws
  /// Sends the refresh token exactly once and validates output against the original identity, nonce, and binding.
  ///
  /// Never retries an unknown rotation outcome automatically. Cooperate with task cancellation; see <doc:ProvidersAndExtensions>.
  func refresh(token: String, identity: AuthIdentity, nonce: String?, binding: AuthIDTokenBinding?)
    async throws
    -> AuthTokenResponse
  /// Performs separate provider logout. Missing support must produce `unsupportedProviderFeature`.
  func logoutAtProvider() async throws
}

extension AuthOIDCAdapter {
  /// A no-op default for adapters that need no separate refresh preparation.
  public func prepareRefresh() async throws {}
}
