import CryptoKit
import Foundation

/// Explicit login choices interpreted by the configured adapter. Hosted services own OTP flows.
public enum AuthLoginChoice: Sendable, Equatable {
  /// Lets the OIDC service present its configured sign-in methods.
  case serviceSelection
  /// Selects a hosted connection name, or "apple"/"github" with DirectAuthAdapter.
  /// Hosted connection names alone do not create a provider integration.
  case connection(String)
}

/// Provider-specific resource selection is explicit; an audience parameter is not assumed to be universal OAuth.
public enum AuthAPIResource: Sendable, Equatable {
  /// Sends the nonempty API identifier as the provider-specific `audience` parameter.
  case auth0Audience(String)
  /// Sends the resource identifier as the OAuth `resource` parameter. The URL identifies a resource, not an HTTP endpoint.
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
  /// The OIDC issuer's exact HTTPS URL without user information, query, or fragment.
  public let issuer: URL
  /// The public client ID registered with the issuer. The application must not contain a client secret.
  public let clientID: String
  /// The registered login callback. Custom schemes work on the minimum platforms; HTTPS requires iOS 17.4 or macOS 14.4.
  public let redirectURI: URL
  /// The total deadline in seconds for preparation, refresh, validation, and persistence; defaults to 60 and must be greater than 0 and at most 3600.
  public let refreshTimeout: TimeInterval
  /// Unique OAuth scopes. Must contain `openid`; defaults to `openid` and `offline_access`.
  public let scopes: [String]
  /// One explicit API resource that also participates in Keychain isolation.
  public let apiResource: AuthAPIResource
  /// The registered callback for separate provider logout; `nil` disables that feature.
  public let postLogoutRedirectURI: URL?
  /// An application and environment identifier such as `com.example.app.production`; included in storage and session-lock hashing.
  public let keychainNamespace: String
  /// Choices allowed for explicit login. Defaults to the service's own method selection.
  public let loginChoices: [AuthLoginChoice]
  /// Requests an ephemeral system-browser session. Defaults to `false`; this does not guarantee provider logout.
  public let ephemeralBrowserSession: Bool
  /// Additional explicit HTTPS origins for discovery endpoints. The issuer origin is always allowed; defaults to none.
  public let trustedEndpointOrigins: [URL]
  /// Additional allowed ID-token `aud` values. The client ID must still be present; defaults to none.
  public let trustedIDTokenAudiences: [String]

  /// Creates and validates a configuration for one public OIDC client and API resource.
  ///
  /// See <doc:Configuration> for defaults, URL rules, and storage identity.
  /// - Throws: `AuthError.invalidConfiguration` when fields or callback support are invalid.
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
