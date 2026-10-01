import AuthenticationServices
import Foundation

/// Presents native Sign in with Apple using the application's explicit presentation window.
@MainActor
public final class SystemAppleAuthorization: NSObject, DirectAppleAuthorization,
  ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding
{
  private let anchor: @MainActor @Sendable () -> ASPresentationAnchor
  private var controller: ASAuthorizationController?
  private var operationID: UUID?
  private var pending: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

  /// Creates an authorizer with the active application window supplied on MainActor.
  public init(presentationAnchor: @escaping @MainActor @Sendable () -> ASPresentationAnchor) {
    anchor = presentationAnchor
  }

  /// Presents native Apple authorization using the exact nonce and state.
  public func authorize(nonce: String, state: String) async throws
    -> ASAuthorizationAppleIDCredential
  {
    guard controller == nil else { throw AuthError.loginAlreadyInProgress }
    try Task.checkCancellation()
    let id = UUID()
    operationID = id
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.nonce = nonce
        request.state = state
        let controller = ASAuthorizationController(authorizationRequests: [request])
        pending = continuation
        self.controller = controller
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
      }
    } onCancel: {
      Task { @MainActor [weak self] in if self?.operationID == id { self?.cancel() } }
    }
  }

  /// Cancels native authorization and completes its consumer exactly once.
  public func cancel() {
    controller?.cancel()
    finish(.failure(AuthError.cancelled))
  }

  /// Supplies the application window to AuthenticationServices.
  public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor
  {
    anchor()
  }

  /// Returns provider evidence without asserting a verified application identity.
  public func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    guard self.controller === controller else { return }
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
      finish(.failure(AuthError.providerRejected))
      return
    }
    finish(.success(credential))
  }

  /// Maps authorization failure to redacted library errors.
  public func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithError error: Error
  ) {
    guard self.controller === controller else { return }
    finish(
      .failure(
        (error as? ASAuthorizationError)?.code == .canceled
          ? AuthError.cancelled : AuthError.providerRejected))
  }

  private func finish(_ result: Result<ASAuthorizationAppleIDCredential, Error>) {
    let continuation = pending
    pending = nil
    operationID = nil
    controller = nil
    continuation?.resume(with: result)
  }
}
