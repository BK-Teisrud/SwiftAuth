import Observation

/// Thin SwiftUI-friendly state adapter without screens or navigation.
@MainActor @Observable
public final class AuthSessionObserver {
  /// The latest observed token-free state on MainActor, suitable for SwiftUI observation.
  public private(set) var state: AuthState = .restoring
  @ObservationIgnored private var observation: Task<Void, Never>?
  /// Starts observing the client's state stream. Retain the observer while the UI needs it; deinitialization cancels the subscription.
  public init(client: AuthClient) {
    observation = Task { [weak self] in
      let stream = await client.states()
      for await value in stream {
        guard !Task.isCancelled else { break }
        self?.state = value
      }
    }
  }
  deinit { observation?.cancel() }
}
