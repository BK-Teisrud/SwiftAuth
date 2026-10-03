import Auth
import Foundation

/// Proposed API contract for the existing backend. No automatic request retries or redirects.
final class AppAuthBackend: DirectAuthBackend, Sendable {
  let baseURL: URL
  private let applicationID: String
  private let session: URLSession
  private let redirectPolicy: NoAuthRedirects

  init(baseURL: URL, applicationID: String, protocolClasses: [AnyClass]? = nil) {
    self.baseURL = baseURL
    self.applicationID = applicationID
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 60
    config.urlCache = nil
    config.httpCookieStorage = nil
    config.protocolClasses = protocolClasses
    let delegate = NoAuthRedirects()
    redirectPolicy = delegate
    session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
  }

  deinit { session.invalidateAndCancel() }

  func begin(
    provider: DirectAuthProvider, state: String, nonce: String?, codeChallenge: String?,
    redirectURI: URL
  ) async throws -> DirectAuthTransaction {
    struct Body: Encodable {
      let applicationID: String
      let provider: DirectAuthProvider
      let state: String
      let nonce: String?
      let codeChallenge: String?
      let codeChallengeMethod: String?
      let redirectURI: String
    }
    struct Response: Decodable { let transactionID: String }
    let body = Body(
      applicationID: applicationID, provider: provider, state: state,
      nonce: nonce, codeChallenge: codeChallenge,
      codeChallengeMethod: codeChallenge == nil ? nil : "S256",
      redirectURI: redirectURI.absoluteString)
    let data = try await send(path: "auth/direct/begin", body: JSONEncoder().encode(body))
    let response: Response = try decode(data)
    guard !response.transactionID.isEmpty else { throw AuthError.tokenExchange }
    return .init(id: response.transactionID)
  }

  func exchange(_ proof: DirectAuthProof) async throws -> AuthTokenResponse {
    struct Body: Encodable {
      let applicationID: String
      let provider: DirectAuthProvider
      let transactionID: String
      let authorizationCode: String
      let identityToken: String?
      let codeVerifier: String?
    }
    let body = Body(
      applicationID: applicationID, provider: proof.provider,
      transactionID: proof.transactionID, authorizationCode: proof.authorizationCode,
      identityToken: proof.identityToken, codeVerifier: proof.codeVerifier)
    return try sessionResponse(
      await send(path: "auth/direct/exchange", body: JSONEncoder().encode(body)))
  }

  func refresh(token: String, identity: AuthIdentity) async throws -> AuthTokenResponse {
    struct Body: Encodable {
      let applicationID: String
      let refreshToken: String
    }
    let body = Body(applicationID: applicationID, refreshToken: token)
    let response = try sessionResponse(
      await send(
        path: "auth/session/refresh",
        body: JSONEncoder().encode(body), refreshing: true))
    guard response.identity == identity, let replacement = response.refreshToken,
      !replacement.isEmpty
    else { throw AuthError.refreshRejected }
    return response
  }

  func user(accessToken: String) async throws -> BackendUser {
    try decode(await send(path: "auth/me", method: "GET", accessToken: accessToken))
  }

  func revoke(accessToken: String) async throws {
    _ = try await send(path: "auth/session/revoke", body: Data("{}".utf8), accessToken: accessToken)
  }

  private func sessionResponse(_ data: Data) throws -> AuthTokenResponse {
    struct Response: Decodable {
      let subject: String
      let accessToken: String
      let expiresAt: Double
      let refreshToken: String?
    }
    let response: Response = try decode(data)
    guard !response.subject.isEmpty, !response.accessToken.isEmpty,
      response.expiresAt.isFinite, response.expiresAt > Date().timeIntervalSince1970,
      response.refreshToken?.isEmpty != true
    else { throw AuthError.tokenExchange }
    return .init(
      identity: .init(issuer: baseURL.absoluteString, subject: response.subject),
      accessToken: response.accessToken,
      expiresAt: Date(timeIntervalSince1970: response.expiresAt),
      refreshToken: response.refreshToken)
  }

  private func decode<T: Decodable>(_ data: Data) throws -> T {
    do { return try JSONDecoder().decode(T.self, from: data) } catch {
      throw AuthError.tokenExchange
    }
  }

  private func send(
    path: String, method: String = "POST", body: Data? = nil,
    accessToken: String? = nil, refreshing: Bool = false
  ) async throws -> Data {
    guard baseURL.scheme == "https", baseURL.host != nil,
      baseURL.user == nil, baseURL.password == nil,
      baseURL.query == nil, baseURL.fragment == nil
    else { throw AuthError.invalidConfiguration }
    try Task.checkCancellation()
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = method
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    if let accessToken {
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }
    do {
      let (bytes, response) = try await session.bytes(for: request)
      guard let http = response as? HTTPURLResponse else { throw AuthError.tokenExchange }
      if refreshing && http.statusCode == 401 { throw AuthError.refreshRejected }
      guard (200..<300).contains(http.statusCode) else {
        switch http.statusCode {
        case 401, 403: throw AuthError.providerRejected
        case 404, 501: throw AuthError.unsupportedProviderFeature
        case 500...599:
          throw refreshing ? AuthError.refreshOutcomeUnknown : AuthError.serviceUnavailable
        default: throw AuthError.tokenExchange
        }
      }
      guard response.expectedContentLength <= 65_536 else { throw AuthError.tokenExchange }
      var data = Data()
      for try await byte in bytes {
        guard data.count < 65_536 else { throw AuthError.tokenExchange }
        data.append(byte)
      }
      try Task.checkCancellation()
      return data
    } catch let error as AuthError { throw error } catch is CancellationError {
      throw CancellationError()
    } catch {
      if Task.isCancelled { throw CancellationError() }
      throw refreshing ? AuthError.refreshOutcomeUnknown : AuthError.networkUnavailable
    }
  }
}

private final class NoAuthRedirects: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
