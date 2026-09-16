import CryptoKit
import Foundation

/// Explicit provider connection choices; the service owns passwordless OTP and identity-provider flows.
public enum AuthLoginChoice: Sendable, Equatable {
  /// Lar OIDC-tjenesten vise sine konfigurerte innloggingsmetoder.
  case serviceSelection
  /// Velger tjenestens eksakte connection-navn. Navnet oppretter ingen Apple-, Vipps- eller OTP-integrasjon.
  case connection(String)
}

/// Provider-specific resource selection is explicit; an audience parameter is not assumed to be universal OAuth.
public enum AuthAPIResource: Sendable, Equatable {
  /// Sender den ikke-tomme API-identifikatoren som leverandørparameteren `audience`.
  case auth0Audience(String)
  /// Sender ressursidentifikatoren som OAuth-parameteren `resource`. URL-en identifiserer ressursen; den er ikke et HTTP-endepunkt.
  case oauthResource(URL)

  var storageIdentity: [String] {
    switch self {
    case .auth0Audience(let value): return ["auth0Audience", value]
    case .oauthResource(let url): return ["oauthResource", url.absoluteString]
    }
  }
}

/// One public OIDC client and one API resource. No client-secret support.
public struct AuthConfiguration: Sendable, Equatable {
  /// OIDC-utstederens eksakte HTTPS-URL uten brukerinformasjon, query eller fragment.
  public let issuer: URL
  /// Offentlig klient-ID registrert hos utstederen. Ingen klienthemmelighet skal ligge i appen.
  public let clientID: String
  /// Registrert login-callback. Custom scheme støttes fra minimumsversjonen; HTTPS krever iOS 17.4 eller macOS 14.4.
  public let redirectURI: URL
  /// Samlet frist i sekunder for forberedelse, refresh, validering og lagring; standard 60, gyldig intervall større enn 0 til og med 3600.
  public let refreshTimeout: TimeInterval
  /// Unike OAuth-scopes. Må inneholde `openid`; standard er `openid` og `offline_access`.
  public let scopes: [String]
  /// Én eksplisitt API-ressurs som også inngår i Keychain-isolasjonen.
  public let apiResource: AuthAPIResource
  /// Registrert callback for separat utlogging hos leverandøren; `nil` deaktiverer denne funksjonen.
  public let postLogoutRedirectURI: URL?
  /// App- og miljøidentifikator, eksempelvis `no.firma.app.production`. Inngår i hash for lagring og sesjonslås.
  public let keychainNamespace: String
  /// Tillatte valg ved eksplisitt login. Standard er bare tjenestens egen metodevelger.
  public let loginChoices: [AuthLoginChoice]
  /// Ber systemnettleseren om en midlertidig nettlesersesjon. Standard `false`; dette er ikke en garanti for leverandørutlogging.
  public let ephemeralBrowserSession: Bool
  /// Ekstra eksplisitte HTTPS-origins for discovery-endepunkter. Utstederens origin er alltid tillatt; standard er ingen ekstra.
  public let trustedEndpointOrigins: [URL]
  /// Ekstra tillatte `aud`-verdier i ID-tokenet. Klient-ID må fortsatt være inkludert; standard er ingen ekstra.
  public let trustedIDTokenAudiences: [String]

  /// Oppretter og validerer en konfigurasjon for én offentlig OIDC-klient og API-ressurs.
  ///
  /// Se <doc:Configuration> for alle standardverdier, URL-regler og lagringsidentitet.
  /// - Throws: `AuthError.invalidConfiguration` dersom feltene eller callback-støtten er ugyldige.
  public init(
    issuer: URL, clientID: String, redirectURI: URL,
    scopes: [String] = ["openid", "offline_access"], apiResource: AuthAPIResource,
    postLogoutRedirectURI: URL? = nil, keychainNamespace: String,
    loginChoices: [AuthLoginChoice] = [.serviceSelection], ephemeralBrowserSession: Bool = false,
    trustedEndpointOrigins: [URL] = [], trustedIDTokenAudiences: [String] = [],
    refreshTimeout: TimeInterval = 60
  ) throws {
    guard refreshTimeout.isFinite, refreshTimeout > 0, refreshTimeout <= 3600,
      issuer.scheme == "https", issuer.host != nil, issuer.user == nil, issuer.password == nil,
      issuer.query == nil, issuer.fragment == nil,
      !clientID.isEmpty, apiResource.storageIdentity.allSatisfy({ !$0.isEmpty }),
      Self.validResource(apiResource),
      trustedIDTokenAudiences.allSatisfy({ !$0.isEmpty }),
      Set(trustedIDTokenAudiences).count == trustedIDTokenAudiences.count,
      trustedEndpointOrigins.allSatisfy({
        $0.scheme == "https" && $0.host != nil && $0.user == nil && $0.password == nil
          && $0.query == nil && $0.fragment == nil && ($0.path.isEmpty || $0.path == "/")
      }),
      !keychainNamespace.isEmpty, !loginChoices.isEmpty,
      scopes.contains("openid"), Set(scopes).count == scopes.count,
      scopes.allSatisfy({
        !$0.isEmpty
          && $0.unicodeScalars.allSatisfy {
            $0.value >= 0x21 && $0.value <= 0x7E && $0 != "\"" && $0 != "\\"
          }
      }),
      Self.validCallback(redirectURI), postLogoutRedirectURI.map(Self.validCallback) ?? true,
      loginChoices.allSatisfy({
        if case .connection(let name) = $0 { return !name.isEmpty }
        return true
      })
    else { throw AuthError.invalidConfiguration }
    self.issuer = issuer
    self.clientID = clientID
    self.redirectURI = redirectURI
    self.refreshTimeout = refreshTimeout
    self.scopes = scopes
    self.apiResource = apiResource
    self.postLogoutRedirectURI = postLogoutRedirectURI
    self.keychainNamespace = keychainNamespace
    self.loginChoices = loginChoices
    self.ephemeralBrowserSession = ephemeralBrowserSession
    self.trustedEndpointOrigins = trustedEndpointOrigins
    self.trustedIDTokenAudiences = trustedIDTokenAudiences
  }

  private static func validResource(_ resource: AuthAPIResource) -> Bool {
    if case .oauthResource(let url) = resource {
      return url.scheme != nil && url.fragment == nil && url.user == nil && url.password == nil
    }
    return true
  }

  private static func validCallback(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else { return false }
    if scheme == "https" {
      if #available(iOS 17.4, macOS 14.4, *) {
        return url.host != nil && url.user == nil && url.password == nil && url.port == nil
          && url.query == nil && url.fragment == nil && !url.path.isEmpty
      }
      return false
    }
    return !["http", "file", "data", "javascript"].contains(scheme)
      && (url.host != nil || !url.path.isEmpty) && url.user == nil && url.password == nil
      && url.port == nil
      && url.query == nil && url.fragment == nil
  }

  var storageService: String {
    // Length-delimited JSON prevents namespace collisions; hash avoids exposing configuration in service names.
    let values = [keychainNamespace, issuer.absoluteString, clientID] + apiResource.storageIdentity
    let data = try! JSONEncoder().encode(values)
    return "Auth." + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
