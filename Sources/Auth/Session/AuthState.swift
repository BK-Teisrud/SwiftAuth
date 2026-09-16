import Foundation

/// Stable identity uses issuer plus subject, never email.
public struct AuthIdentity: Sendable, Equatable, Codable {
  /// Verifisert utstederidentifikator, tilsvarende ID-tokenets `iss`.
  public let issuer: String
  /// Stabil brukeridentifikator fra `sub`; skal kombineres med utsteder, ikke erstattes med e-post.
  public let subject: String
  /// Oppretter en identitetsverdi. Initialisatoren utfører ingen signatur- eller claim-validering; adapteren har dette ansvaret.
  public init(issuer: String, subject: String) {
    self.issuer = issuer
    self.subject = subject
  }
}

/// Contains no credentials. Temporary failures do not silently discard local identity.
public enum AuthState: Sendable, Equatable {
  /// Starttilstand før eksplisitt gjenoppretting. Lagringsfeil kan la tilstanden bli stående her.
  case restoring
  /// Ingen aktiv lokal identitet. Et valgfritt problem beskriver eksempelvis mislykket sletting.
  case signedOut(problem: AuthError? = nil)
  /// Eksplisitt interaktiv innlogging pågår. API-forespørsler åpner aldri innlogging automatisk.
  case signingIn
  /// Lokal identitet er kjent. Et problem kan kreve tiltak; tilstanden garanterer ikke gyldig API-token eller serverrettigheter.
  case signedIn(AuthIdentity, problem: AuthError? = nil)
  /// En kjent eller ukjent identitet trenger ny eksplisitt innlogging. Årsaken bevares ved mislykket eller avbrutt innlogging.
  case reauthenticationRequired(AuthIdentity?, reason: AuthError)
}
