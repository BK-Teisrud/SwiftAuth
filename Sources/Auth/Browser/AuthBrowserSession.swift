import AuthenticationServices
import Foundation

/// Injectable system-browser boundary. Implementations must never use an embedded WKWebView for login.
@MainActor public protocol AuthBrowserSession: AnyObject, Sendable {
  /// Åpner systemnettleser mot URL-en og returnerer callback for videre protokollvalidering.
  ///
  /// `ephemeral` ber om midlertidig nettlesersesjon. Implementasjonen må håndtere kansellering og aldri bruke innebygd WKWebView.
  func authenticate(url: URL, callbackURI: URL, ephemeral: Bool) async throws -> URL
  /// Avslutter aktiv nettleseroperasjon og fullfører ventende konsument nøyaktig én gang.
  func cancel()
}

/// iOS 17-compatible custom-scheme callback API. The app supplies its presentation window explicitly.
@MainActor
public final class SystemAuthBrowser: NSObject, AuthBrowserSession,
  ASWebAuthenticationPresentationContextProviding
{
  private let anchor: @MainActor @Sendable () -> ASPresentationAnchor
  private var session: ASWebAuthenticationSession?
  private var operationID: UUID?
  private var pending: CheckedContinuation<URL, Error>?
  /// Oppretter systemnettleseren med en closure som returnerer appens aktive presentasjonsvindu på MainActor.
  public init(presentationAnchor: @escaping @MainActor @Sendable () -> ASPresentationAnchor) {
    self.anchor = presentationAnchor
  }
  /// Leverer appens eksplisitte vindu til AuthenticationServices. Appen eier vinduets livssyklus.
  public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    anchor()
  }
  /// Starter én ASWebAuthenticationSession og returnerer callback-URL uten å tolke OIDC-claims.
  ///
  /// Custom scheme støttes fra minimumsplattformen; HTTPS krever iOS 17.4 eller macOS 14.4.
  /// - Throws: `cancelled`, `browserPresentation`, `loginAlreadyInProgress`, `unsupportedProviderFeature` eller task-kansellering.
  public func authenticate(url: URL, callbackURI: URL, ephemeral: Bool) async throws -> URL {
    guard session == nil else { throw AuthError.loginAlreadyInProgress }
    try Task.checkCancellation()
    let id = UUID()
    operationID = id
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        pending = continuation
        let completion: ASWebAuthenticationSession.CompletionHandler = {
          [weak self] result, error in
          Task { @MainActor in
            guard let self, self.operationID == id else { return }
            if let result {
              self.finish(.success(result))
            } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
              self.finish(.failure(AuthError.cancelled))
            } else {
              self.finish(.failure(AuthError.browserPresentation))
            }
          }
        }
        let operation: ASWebAuthenticationSession
        if callbackURI.scheme == "https" {
          if #available(iOS 17.4, macOS 14.4, *), let host = callbackURI.host {
            operation = ASWebAuthenticationSession(
              url: url, callback: .https(host: host, path: callbackURI.path),
              completionHandler: completion)
          } else {
            finish(.failure(AuthError.unsupportedProviderFeature))
            return
          }
        } else {
          operation = ASWebAuthenticationSession(
            url: url, callbackURLScheme: callbackURI.scheme, completionHandler: completion)
        }
        operation.presentationContextProvider = self
        operation.prefersEphemeralWebBrowserSession = ephemeral
        session = operation
        if !operation.start() { finish(.failure(AuthError.browserPresentation)) }
      }
    } onCancel: {
      Task { @MainActor [weak self] in if self?.operationID == id { self?.cancel() } }
    }
  }
  /// Kansellerer systemnettleseren og fullfører ventende autentisering med `AuthError.cancelled`. Uten aktiv operasjon skjer ingenting.
  public func cancel() {
    session?.cancel()
    finish(.failure(AuthError.cancelled))
  }
  private func finish(_ result: Result<URL, Error>) {
    let continuation = pending
    pending = nil
    session = nil
    operationID = nil
    continuation?.resume(with: result)
  }
}
