import Foundation

/// Verified claims that must remain bound to the original authentication across refresh and restart.
public struct AuthIDTokenBinding: Codable, Sendable, Equatable {
  /// Sortert liste med verifiserte ID-token-audiences som skal bevares gjennom refresh og restart.
  public let audiences: [String]
  /// Opprinnelig verifisert `auth_time` i sekunder siden epoch, dersom claimet var til stede.
  public let authenticationTime: Double?
  /// Oppretter bindingsverdi og sorterer audiences. Utfører ingen kryptografisk validering.
  public init(audiences: [String], authenticationTime: Double? = nil) {
    self.audiences = audiences.sorted()
    self.authenticationTime = authenticationTime
  }
}

/// Sensitive adapter output, never exposed by AuthState. Only return credentials after complete OIDC validation.
public struct AuthTokenResponse: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  /// Identitet fra fullstendig verifisert ID-token eller bevart refresh-identitet.
  public let identity: AuthIdentity
  /// Sensitivt bearer-token for konfigurert API; skal aldri logges.
  public let accessToken: String
  /// Absolutt utløp beregnet fra responsens levetid. Klienten krever en dato i fremtiden.
  public let expiresAt: Date
  /// Sensitivt refresh-token. Ved refresh betyr `nil` at eksisterende token beholdes; ved login betyr det ingen lagret refresh.
  public let refreshToken: String?
  /// Opprinnelig tilfeldig OIDC-nonce som lagres for senere validering av refresh-ID-token.
  public let loginNonce: String?
  /// Verifiserte audiences og autentiseringstid for binding på tvers av refresh og restart.
  public let idTokenBinding: AuthIDTokenBinding?
  /// Oppretter sensitiv adapterrespons. Verifiser protokoll, signatur og claims før konstruksjon.
  ///
  /// `refreshToken` må oppgis eksplisitt, eventuelt som `nil`. Nonce og binding har standard `nil`; native-adapteren fyller dem fra verifisert login.
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
  /// Redigert beskrivelse som aldri inkluderer identitet eller credentials.
  public var description: String { "AuthTokenResponse(<REDACTED>)" }
  /// Samme redigerte verdi som ``description``; inneholder aldri tokens.
  public var debugDescription: String { description }
}

/// Provider boundary. New adapters must validate discovery, PKCE, state, nonce, signature and OIDC claims. Use Apple cryptographic APIs.
/// Never return decoded-but-unverified ID-token identity. Never automatically retry rotating refresh requests.
@MainActor public protocol AuthOIDCAdapter: Sendable {
  /// Uforanderlig klientkonfigurasjon som også bestemmer sesjonens lagringsidentitet.
  var configuration: AuthConfiguration { get }
  /// Utfører eksplisitt login og returnerer bare fullstendig verifisert resultat. Ingen standard for metodevalget i protokollen.
  func login(choice: AuthLoginChoice) async throws -> AuthTokenResponse
  /// Avbryter nettleseroperasjon og ugyldiggjør sene resultater uten å slette klientens lokale sesjon.
  func cancelLogin() async
  /// Forbereder eksempelvis discovery uten å sende refresh-token. Feil her kan forsøkes igjen uten rotasjonskarantene.
  func prepareRefresh() async throws
  /// Sender refresh-token nøyaktig én gang og validerer resultatet mot opprinnelig identitet, nonce og binding.
  ///
  /// Ingen automatisk retry ved ukjent rotasjonsresultat. Samarbeid med task-kansellering; se <doc:ProvidersAndExtensions>.
  func refresh(token: String, identity: AuthIdentity, nonce: String?, binding: AuthIDTokenBinding?)
    async throws
    -> AuthTokenResponse
  /// Utfører separat leverandørutlogging. Manglende støtte skal gi `unsupportedProviderFeature`.
  func logoutAtProvider() async throws
}

extension AuthOIDCAdapter {
  /// Standardimplementasjon uten arbeid for adaptere som ikke trenger separat refresh-forberedelse.
  public func prepareRefresh() async throws {}
}
