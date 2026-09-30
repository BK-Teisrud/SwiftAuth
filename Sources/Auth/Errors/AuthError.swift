import Foundation

/// Safe, structured errors. Provider descriptions, URLs and credentials are never retained here.
public enum AuthError: Error, Sendable, Equatable {
  /// Another live client or process owns the same storage identity.
  case sessionAlreadyInUse
  /// Configuration violates validation rules and must be corrected before use.
  case invalidConfiguration
  /// The network was unavailable or refresh preparation timed out before credentials were sent.
  case networkUnavailable
  /// The service returned a temporary server failure before a safe retry was ruled out.
  case serviceUnavailable
  /// The service rejected login; contains no raw provider description.
  case providerRejected
  /// Discovery, metadata, or endpoint trust could not be validated.
  case discovery
  /// The system browser could not be presented or completed as expected.
  case browserPresentation
  /// Interactive authentication was cancelled by the user or client.
  case cancelled
  /// A competing interactive operation, browser shutdown, or incompatible session operation is in progress.
  case loginAlreadyInProgress
  /// The callback URL, state, issuer, or authorization result was invalid.
  case callback
  /// The token response or code exchange was invalid; no raw token response is retained.
  case tokenExchange
  /// An ID token, signature, key, or claim could not be verified.
  case idTokenValidation
  /// A Keychain operation failed with an explicit OSStatus; raw credentials are never included.
  case keychain(status: Int32)
  /// Both the durable logout marker and deletion failed. Memory is cleared, but data may remain on disk.
  case logoutPersistenceUnavailable
  /// Session format, persistence, file marker, or locking could not be handled safely.
  case storage
  /// The service rejected refresh, for example with `invalid_grant`. New explicit login is required.
  case refreshRejected
  /// Refresh may have rotated at the service without a known local result. The token is quarantined durably.
  case refreshOutcomeUnknown
  /// The session needs explicit login, for example because an expired token cannot be refreshed.
  case reauthenticationRequired
  /// The operation belongs to an earlier session or unknown token. Do not use this error to log out a newer user.
  case operationInvalidated
  /// A required feature or callback capability is unavailable from the service or platform.
  case unsupportedProviderFeature
}

/// Suggested UI action; a retry never overrides quarantine of an uncertain rotating refresh.
public enum AuthRecoveryAction: Sendable, Equatable {
  /// Suggest another explicit attempt after the cause is resolved. Never overrides refresh quarantine.
  case retry
  /// Offer a new explicit login. API token acquisition does not open the browser.
  case signIn
  /// Correct application or service configuration before trying again.
  case configure
  /// Wait for storage or repair the storage failure, then retry incomplete local logout.
  case waitForStorage
  /// No automatic action. Handle cancellation, concurrency, or stale-session work in the application flow.
  case none
}
extension AuthError {
  /// Recommended application or UI action. The value performs no retry, logout, or login. See <doc:ErrorsAndRecovery>.
  public var recoveryAction: AuthRecoveryAction {
    switch self {
    case .networkUnavailable, .serviceUnavailable, .browserPresentation: return .retry
    case .refreshRejected, .refreshOutcomeUnknown, .reauthenticationRequired: return .signIn
    case .invalidConfiguration, .discovery, .unsupportedProviderFeature: return .configure
    case .keychain, .storage, .logoutPersistenceUnavailable: return .waitForStorage
    case .cancelled, .operationInvalidated, .loginAlreadyInProgress, .sessionAlreadyInUse:
      return .none
    case .providerRejected, .callback, .tokenExchange, .idTokenValidation: return .signIn
    }
  }
}
