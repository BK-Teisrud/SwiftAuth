import Foundation

/// Stable identity uses issuer plus subject, never email.
public struct AuthIdentity: Sendable, Equatable, Codable {
  /// The verified OIDC issuer or the configured backend's identity namespace.
  public let issuer: String
  /// The stable OIDC subject or internal backend user ID; combine it with issuer, never email.
  public let subject: String
  /// Creates an identity value. This initializer performs no signature or claim validation; the adapter owns that responsibility.
  public init(issuer: String, subject: String) {
    self.issuer = issuer
    self.subject = subject
  }
}

/// Contains no credentials. Temporary failures do not silently discard local identity.
public enum AuthState: Sendable, Equatable {
  /// Initial state before explicit restore. A storage failure can leave the client in this state.
  case restoring
  /// No active local identity. An optional issue can describe a failed deletion or similar condition.
  case signedOut(problem: AuthError? = nil)
  /// Explicit interactive login is in progress. API requests never open login automatically.
  case signingIn
  /// Local identity is known. An issue may require action; this state does not guarantee a valid API token or server authorization.
  case signedIn(AuthIdentity, problem: AuthError? = nil)
  /// A known or unknown identity requires new explicit login. Failed or cancelled login preserves the reason.
  case reauthenticationRequired(AuthIdentity?, reason: AuthError)
}
