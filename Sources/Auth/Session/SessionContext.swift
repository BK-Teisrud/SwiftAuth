import Foundation

struct SessionContext {
  var id = UUID()
  var stored: StoredSession?
  var access: AuthTokenResponse?
  var refreshBlocked: AuthError?
  var refreshAfter = Date.distantPast

  mutating func install(_ response: AuthTokenResponse, now: Date) {
    access = response
    let lifetime = max(0, response.expiresAt.timeIntervalSince(now))
    refreshAfter = response.expiresAt.addingTimeInterval(-min(60, lifetime * 0.1))
  }
  func state(problem: AuthError? = nil) -> AuthState {
    guard let identity = access?.identity ?? stored?.identity else {
      return .signedOut(problem: problem)
    }
    if let refreshBlocked, refreshBlocked != .refreshOutcomeUnknown {
      return .reauthenticationRequired(identity, reason: refreshBlocked)
    }
    return .signedIn(identity, problem: refreshBlocked ?? problem)
  }
}
