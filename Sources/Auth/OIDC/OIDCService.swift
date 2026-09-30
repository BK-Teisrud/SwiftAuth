import CoreFoundation
import Foundation
import Networking

/// Only typed, immutable token fields cross the service/browser actor boundary.
struct OIDCTokenResponse: Sendable {
  let accessToken: String
  let expiresIn: TimeInterval
  let refreshToken: String?
  let idToken: String?
  init(_ json: [String: Any]) throws {
    guard let access = json["access_token"] as? String, !access.isEmpty, access.utf8.count <= 16384,
      (json["token_type"] as? String)?.lowercased() == "bearer",
      let expiry = json["expires_in"] as? NSNumber, CFGetTypeID(expiry) != CFBooleanGetTypeID(),
      expiry.doubleValue.isFinite, expiry.doubleValue > 0, expiry.doubleValue <= 31_536_000
    else { throw AuthError.tokenExchange }
    if let refresh = json["refresh_token"] {
      guard let value = refresh as? String, !value.isEmpty, value.utf8.count <= 16384 else {
        throw AuthError.tokenExchange
      }
      refreshToken = value
    } else {
      refreshToken = nil
    }
    if let token = json["id_token"] {
      guard let value = token as? String else { throw AuthError.idTokenValidation }
      idToken = value
    } else {
      idToken = nil
    }
    accessToken = access
    expiresIn = expiry.doubleValue
  }
}

struct OIDCMetadata: Sendable {
  let authorizationEndpoint: URL
  let tokenEndpoint: URL
  let jwksURI: URL
  let endSessionEndpoint: URL?
}

/// Network caches, protocol parsing and Apple signature verification run outside MainActor.
actor OIDCService {
  private let configuration: AuthConfiguration
  private let transport: any HTTPTransport
  private let now: @Sendable () -> Date
  private var metadata: OIDCMetadata?
  private var metadataExpiresAt = Date.distantPast
  private var cachedJWKS: (data: Data, expires: Date)?
  init(
    configuration: AuthConfiguration, transport: any HTTPTransport,
    now: @escaping @Sendable () -> Date
  ) {
    self.configuration = configuration
    self.transport = transport
    self.now = now
  }
  func discover() async throws -> OIDCMetadata {
    if let metadata, now() < metadataExpiresAt { return metadata }
    do {
      let data = try await send(
        configuration.issuer.appendingPathComponent(".well-known/openid-configuration"),
        limit: 65536)
      let json: [String: Any]
      do {
        json = try StrictJSON.object(data)
      } catch {
        throw AuthError.discovery
      }
      guard json["issuer"] as? String == configuration.issuer.absoluteString,
        (json["response_types_supported"] as? [String])?.contains("code") == true,
        (json["code_challenge_methods_supported"] as? [String])?.contains("S256") == true,
        (json["id_token_signing_alg_values_supported"] as? [String])?.contains("RS256") == true,
        json["token_endpoint_auth_methods_supported"] == nil
          || (json["token_endpoint_auth_methods_supported"] as? [String])?.contains("none") == true,
        json["grant_types_supported"] == nil
          || (json["grant_types_supported"] as? [String])?.contains("authorization_code") == true
      else { throw AuthError.discovery }
      func endpoint(_ name: String) throws -> URL {
        guard let text = json[name] as? String, let url = URL(string: text),
          let value = URLComponents(url: url, resolvingAgainstBaseURL: false),
          value.scheme == "https",
          ([configuration.issuer] + configuration.trustedEndpointOrigins).contains(where: {
            $0.host == value.host && ($0.port ?? 443) == (value.port ?? 443)
          }),
          value.user == nil, value.password == nil, value.fragment == nil,
          !(value.queryItems ?? []).contains(where: {
            [
              "client_id", "client_secret", "redirect_uri", "response_type", "scope", "state",
              "nonce", "code_challenge", "code_challenge_method", "grant_type", "code",
              "code_verifier", "refresh_token", "audience", "resource", "post_logout_redirect_uri",
              "connection", "id_token_hint",
            ].contains($0.name)
          })
        else { throw AuthError.discovery }
        return url
      }
      let result = try OIDCMetadata(
        authorizationEndpoint: endpoint("authorization_endpoint"),
        tokenEndpoint: endpoint("token_endpoint"),
        jwksURI: endpoint("jwks_uri"),
        endSessionEndpoint: json["end_session_endpoint"] == nil
          ? nil : endpoint("end_session_endpoint"))
      if metadata?.jwksURI != result.jwksURI { cachedJWKS = nil }
      metadata = result
      metadataExpiresAt = now().addingTimeInterval(300)
      return result
    } catch NetworkingError.http(let failure) {
      throw failure.metadata.statusCode >= 500 ? AuthError.serviceUnavailable : .discovery
    } catch NetworkingError.transport {
      throw AuthError.networkUnavailable
    } catch let error as URLError {
      throw error.code == .cancelled ? AuthError.cancelled : .networkUnavailable
    } catch is CancellationError {
      throw AuthError.cancelled
    } catch { throw error as? AuthError ?? .discovery }
  }
  private func send(_ url: URL, fields: [URLQueryItem]? = nil, limit: Int) async throws -> Data {
    var request = URLRequest(
      url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let fields {
      let client = HTTPClient(configuration: try .init(baseURL: configuration.issuer))
      let prepared = try await client.prepare(
        HTTPRequest(method: .post, path: "", body: .form(fields)))
      request.httpMethod = "POST"
      request.httpBody = prepared.httpBody
      request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    }
    try Task.checkCancellation()
    let response = try await transport.send(
      request, redirectPolicy: .reject,
      options: .init(maximumResponseBytes: limit, maximumErrorBodyBytes: 8192, allowsCaching: false)
    )
    guard response.data.count <= limit, response.receivedBodyBytes <= limit else {
      throw AuthError.tokenExchange
    }
    guard response.metadata.statusCode == 200 else {
      throw NetworkingError.http(
        .init(metadata: response.metadata, body: Data(response.data.prefix(8192))))
    }
    return response.data
  }
  func token(_ endpoint: URL, fields: [URLQueryItem], refresh: Bool) async throws
    -> OIDCTokenResponse
  {
    let json: [String: Any]
    do {
      json = try StrictJSON.object(await send(endpoint, fields: fields, limit: 65536))
    } catch NetworkingError.http(let failure) {
      if refresh, let value = try? StrictJSON.object(failure.body),
        value["error"] as? String == "invalid_grant"
      {
        throw AuthError.refreshRejected
      }
      throw refresh
        ? AuthError.refreshOutcomeUnknown
        : failure.metadata.statusCode >= 500 ? .serviceUnavailable : .providerRejected
    } catch NetworkingError.transport {
      throw refresh ? AuthError.refreshOutcomeUnknown : .networkUnavailable
    } catch let error as URLError {
      throw refresh
        ? AuthError.refreshOutcomeUnknown
        : error.code == .cancelled ? .cancelled : .networkUnavailable
    } catch is CancellationError {
      throw refresh ? AuthError.refreshOutcomeUnknown : .cancelled
    } catch { throw refresh ? AuthError.refreshOutcomeUnknown : .tokenExchange }
    return try OIDCTokenResponse(json)
  }
  private func keys(for token: String, uri: URL) async throws -> Data {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { throw AuthError.idTokenValidation }
    let header = try StrictJSON.object(OIDCEncoding.decode(String(parts[0])))
    guard let kid = header["kid"] as? String else { throw AuthError.idTokenValidation }
    if let cache = cachedJWKS, now() < cache.expires {
      let keys = try StrictJSON.object(cache.data)["keys"] as? [[String: Any]] ?? []
      if keys.contains(where: { $0["kid"] as? String == kid }) { return cache.data }
    }
    do {
      let data = try await send(uri, limit: 262144)
      _ = try StrictJSON.object(data)
      cachedJWKS = (data, now().addingTimeInterval(300))
      return data
    } catch { throw AuthError.idTokenValidation }
  }

  func validated(
    _ json: OIDCTokenResponse, discovery: OIDCMetadata, nonce: String?, identity: AuthIdentity?,
    responseStarted: Date, binding: AuthIDTokenBinding? = nil
  ) async throws -> AuthTokenResponse {
    let access = json.accessToken
    let refresh = json.refreshToken
    let result: AuthIdentity
    var verifiedBinding = binding
    if let token = json.idToken {
      guard identity == nil || binding != nil else { throw AuthError.idTokenValidation }
      let jwks = try await keys(for: token, uri: discovery.jwksURI)
      let verified = try IDTokenValidator(configuration: configuration, now: now).validateVerified(
        token, jwks: jwks, nonce: nonce, identity: identity, accessToken: access, binding: binding,
        refresh: identity != nil)
      result = verified.identity
      verifiedBinding = verified.binding
    } else if let identity {
      result = identity
    } else {
      throw AuthError.idTokenValidation
    }
    return .init(
      identity: result, accessToken: access,
      expiresAt: responseStarted.addingTimeInterval(json.expiresIn), refreshToken: refresh,
      loginNonce: nonce, idTokenBinding: verifiedBinding)
  }
}
