import Observation

/// Thin SwiftUI-friendly state adapter without screens or navigation.
@MainActor @Observable
public final class AuthSessionObserver {
  /// Siste observerte tokenfrie tilstand på MainActor; egnet til SwiftUI-observasjon.
  public private(set) var state: AuthState = .restoring
  @ObservationIgnored private var observation: Task<Void, Never>?
  /// Starter observasjon av klientens tilstandsstrøm. Behold observeren så lenge UI-et trenger den; abonnementet kanselleres ved deinit.
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
