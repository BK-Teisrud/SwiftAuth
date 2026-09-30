import AuthenticationServices
import Foundation

/// Injectable system-browser boundary. Implementations must never use an embedded WKWebView for login.
@MainActor public protocol AuthBrowserSession: AnyObject, Sendable {
  /// Opens the system browser at the URL and returns a callback for further protocol validation.
  ///
  /// `ephemeral` requests a temporary browser session. The implementation must handle cancellation and never use an embedded WKWebView.
  func authenticate(url: URL, callbackURI: URL, ephemeral: Bool) async throws -> URL
  /// Stops the active browser operation and completes its waiting consumer exactly once.
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
  /// Creates a system browser with a closure that returns the application's active presentation window on MainActor.
  public init(presentationAnchor: @escaping @MainActor @Sendable () -> ASPresentationAnchor) {
    self.anchor = presentationAnchor
  }
  /// Supplies the application's explicit window to AuthenticationServices. The application owns the window lifecycle.
  public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    anchor()
  }
  /// Starts one `ASWebAuthenticationSession` and returns its callback URL without interpreting OIDC claims.
  ///
  /// Custom schemes work on the minimum platforms; HTTPS requires iOS 17.4 or macOS 14.4.
  /// - Throws: `cancelled`, `browserPresentation`, `loginAlreadyInProgress`, `unsupportedProviderFeature`, or task cancellation.
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
  /// Cancels the system browser and completes pending authentication with `AuthError.cancelled`. Does nothing without an active operation.
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
