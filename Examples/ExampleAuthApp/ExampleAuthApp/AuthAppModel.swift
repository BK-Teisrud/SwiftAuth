import Auth
import AuthenticationServices
import Foundation
import Observation
import SwiftUI
import UIKit

nonisolated struct AuthSettings: Codable, Equatable, Sendable {
  var backendURL = ""
  var applicationID = "no.teisrud.ExampleAuthApp"
  var githubClientID = ""
  var expectedLogin = ""

  var isComplete: Bool {
    guard let url = URL(string: backendURL) else { return false }
    return url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
      && url.query == nil && url.fragment == nil
      && !applicationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !githubClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

nonisolated struct BackendUser: Decodable, Equatable, Sendable {
  let subject: String
  let name: String?
  let email: String?
  let picture: URL?
  let githubLogin: String?
  let githubID: String?
  var issuer: String = ""
  var displayName: String { name ?? githubLogin ?? subject }

  private enum CodingKeys: String, CodingKey {
    case subject, name, email, picture, githubLogin, githubID
  }
}

enum UserVerification: Equatable {
  case notRequested
  case identityMatches
  case expectedLoginMatches
  case expectedLoginMismatch(expected: String, actual: String?)
  case identityMismatch

  var title: String {
    switch self {
    case .notRequested: "Brukeren er hentet, men ikke sammenlignet"
    case .identityMatches: "Backendprofilen matcher sesjonen"
    case .expectedLoginMatches: "Riktig GitHub-bruker er logget inn"
    case .expectedLoginMismatch(let expected, let actual):
      "Feil bruker: forventet @\(expected), fikk \(actual.map { "@\($0)" } ?? "ukjent")"
    case .identityMismatch: "Backendprofilen matcher ikke sesjonen"
    }
  }

  var symbol: String {
    switch self {
    case .identityMatches, .expectedLoginMatches: "checkmark.seal.fill"
    case .notRequested: "questionmark.circle"
    case .expectedLoginMismatch, .identityMismatch: "xmark.octagon.fill"
    }
  }

  var color: Color {
    switch self {
    case .identityMatches, .expectedLoginMatches: .green
    case .notRequested: .secondary
    case .expectedLoginMismatch, .identityMismatch: .red
    }
  }
}

@MainActor @Observable
final class AuthAppModel {
  private static let settingsKey = "directAuthSettings.v1"
  private(set) var configuration: AuthConfiguration?
  private(set) var state: AuthState = .restoring
  private(set) var user: BackendUser?
  private(set) var verification: UserVerification = .notRequested
  private(set) var isBusy = false
  private(set) var message: String?
  private(set) var messageIsError = false
  var draft = AuthSettings()

  @ObservationIgnored private var client: AuthClient?
  @ObservationIgnored private var stateTask: Task<Void, Never>?
  @ObservationIgnored private var backend: AppAuthBackend?
  @ObservationIgnored private var operationID = UUID()
  @ObservationIgnored private var hasStarted = false

  var isSignedIn: Bool {
    if case .signedIn = state { return true }
    return false
  }

  var statusTitle: String {
    switch state {
    case .restoring: "Gjenoppretter sesjon"
    case .signedOut: "Logget ut"
    case .signingIn: "Logger inn"
    case .signedIn: "Logget inn"
    case .reauthenticationRequired: "Ny innlogging kreves"
    }
  }

  var statusDetail: String {
    switch state {
    case .signedIn(let identity, let problem):
      problem.map { "\(identity.subject) · \(Self.describe($0))" } ?? identity.subject
    case .signedOut(let problem): problem.map(Self.describe) ?? "Ingen lokal sesjon"
    case .reauthenticationRequired(let identity, let reason):
      "\(identity?.subject ?? "Ukjent bruker") · \(Self.describe(reason))"
    case .restoring: "Leser sikker sesjon fra Keychain"
    case .signingIn: "Venter på Apple eller GitHub"
    }
  }

  var statusColor: Color {
    switch state {
    case .signedIn: .green
    case .signingIn, .restoring: .orange
    case .signedOut: .secondary
    case .reauthenticationRequired: .red
    }
  }

  func start() async {
    guard !hasStarted else { return }
    hasStarted = true
    guard let data = UserDefaults.standard.data(forKey: Self.settingsKey),
      let saved = try? JSONDecoder().decode(AuthSettings.self, from: data)
    else {
      state = .signedOut()
      return
    }
    draft = saved
    await configureAndRestore()
  }

  func saveConfigurationAndRestore() async {
    guard !isBusy, draft.isComplete else { return }
    if let data = try? JSONEncoder().encode(draft) {
      UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }
    await configureAndRestore()
  }

  func editConfiguration() {
    guard !isBusy else { return }
    operationID = UUID()
    backend = nil
    stateTask?.cancel()
    stateTask = nil
    client = nil
    configuration = nil
    user = nil
    verification = .notRequested
    state = .signedOut()
    message = "Lagre konfigurasjonen på nytt for å opprette en ny SwiftAuth-klient."
    messageIsError = false
  }

  func signIn(provider: DirectAuthProvider) async {
    guard !isBusy else { return }
    guard let client else { return }
    await perform {
      try await client.login(choice: .connection(provider.rawValue))
      await refreshUser(quiet: true)
    }
  }

  func refreshUser() async { await refreshUser(quiet: false) }

  func signOut() async {
    guard !isBusy, let client else { return }
    await perform {
      var revocationFailed = false
      if let backend {
        do {
          let token = try await client.validAccessToken()
          try await backend.revoke(accessToken: token)
        } catch { revocationFailed = true }
      }
      user = nil
      verification = .notRequested
      try await client.logout()
      message =
        revocationFailed
        ? "Logget ut på enheten. Serverøkten kunne ikke avsluttes; den kan fortsatt være aktiv."
        : "Logget ut på enheten og serveren."
      messageIsError = revocationFailed
    }
  }

  private func configureAndRestore() async {
    guard !isBusy else { return }
    operationID = UUID()
    user = nil
    verification = .notRequested
    backend = nil
    configuration = nil
    isBusy = true
    message = nil
    let previousObserver = stateTask
    previousObserver?.cancel()
    stateTask = nil
    client = nil
    await previousObserver?.value
    do {
      guard draft.isComplete, let backendURL = URL(string: draft.backendURL) else {
        throw AuthError.invalidConfiguration
      }
      let backend = AppAuthBackend(baseURL: backendURL, applicationID: draft.applicationID)
      let adapter = try DirectAuthAdapter(
        backendURL: backendURL, applicationID: draft.applicationID,
        githubClientID: draft.githubClientID,
        redirectURI: URL(string: "exampleauthapp://auth/callback")!,
        keychainNamespace: "no.teisrud.ExampleAuthApp.direct.v1",
        backend: backend,
        apple: SystemAppleAuthorization { Self.presentationAnchor() },
        browser: SystemAuthBrowser { Self.presentationAnchor() },
        ephemeralBrowserSession: true
      )
      let newClient = try await AuthClient(adapter: adapter)
      configuration = adapter.configuration
      self.backend = backend
      client = newClient
      observe(newClient)
      try await newClient.restoreSession()
      if case .signedIn = await newClient.state { await refreshUser(quiet: true) }
    } catch {
      configuration = nil
      show(error)
    }
    isBusy = false
  }

  private func observe(_ client: AuthClient) {
    stateTask = Task { [weak self] in
      let stream = await client.states()
      for await newState in stream {
        guard !Task.isCancelled else { break }
        self?.state = newState
      }
    }
  }

  private func refreshUser(quiet: Bool) async {
    guard let client, let config = configuration, let backend else { return }
    if !quiet && isBusy { return }
    let operation = operationID
    if !quiet {
      isBusy = true
      message = nil
    }
    do {
      let token = try await client.validAccessToken()
      var info = try await backend.user(accessToken: token)
      guard operationID == operation else { return }
      info.issuer = config.issuer.absoluteString
      guard case .signedIn(let identity, _) = await client.state,
        identity.issuer == info.issuer, identity.subject == info.subject
      else {
        user = nil
        verification = .identityMismatch
        throw BackendProfileError.identityMismatch
      }
      user = info
      let expected = draft.expectedLogin.trimmingCharacters(in: .whitespacesAndNewlines)
      if expected.isEmpty || info.githubLogin == nil {
        verification = .identityMatches
      } else if info.githubLogin?.caseInsensitiveCompare(expected) == .orderedSame {
        verification = .expectedLoginMatches
      } else {
        verification = .expectedLoginMismatch(expected: expected, actual: info.githubLogin)
      }
      message = "Profilen ble hentet fra backenden med appens sesjon."
      messageIsError = false
    } catch {
      show(error)
    }
    if !quiet { isBusy = false }
  }

  private func perform(_ operation: () async throws -> Void) async {
    guard !isBusy else { return }
    isBusy = true
    message = nil
    do { try await operation() } catch { show(error) }
    isBusy = false
  }

  private func show(_ error: Error) {
    if let authError = error as? AuthError {
      message = Self.describe(authError)
    } else if error is BackendProfileError {
      message = "Profilen fra backenden matcher ikke den innloggede brukeren."
    } else {
      message =
        "Backenden svarte ikke som forventet. Kontroller at innloggingsendepunktene er implementert."
    }
    messageIsError = true
  }

  private static func presentationAnchor() -> ASPresentationAnchor {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
      ?? scenes.flatMap(\.windows).first
    {
      return window
    }
    preconditionFailure("Innlogging krever en aktiv UIWindowScene")
  }

  private static func describe(_ error: AuthError) -> String {
    switch error {
    case .sessionAlreadyInUse: "En annen SwiftAuth-klient bruker samme sesjon"
    case .invalidConfiguration: "Innloggingskonfigurasjonen er ugyldig"
    case .networkUnavailable: "Nettverket er utilgjengelig"
    case .serviceUnavailable: "Backenden er utilgjengelig eller innloggingsendepunktene mangler"
    case .providerRejected: "Innloggingen ble avvist"
    case .discovery: "OIDC discovery eller endpoint-validering feilet"
    case .browserPresentation: "Systemnettleseren kunne ikke åpnes"
    case .cancelled: "Innloggingen ble avbrutt"
    case .loginAlreadyInProgress: "En innlogging pågår allerede"
    case .callback: "Callback eller state var ugyldig"
    case .tokenExchange: "Utveksling av authorization code feilet"
    case .idTokenValidation: "ID-tokenet kunne ikke valideres"
    case .keychain(let status): "Keychain-feil (\(status))"
    case .logoutPersistenceUnavailable: "Utlogging kunne ikke lagres sikkert"
    case .storage: "Sesjonslagringen feilet"
    case .refreshRejected: "Refresh token ble avvist"
    case .refreshOutcomeUnknown: "Refresh-resultatet er ukjent; logg inn på nytt"
    case .reauthenticationRequired: "Ny innlogging kreves"
    case .operationInvalidated: "Operasjonen tilhørte en eldre sesjon"
    case .unsupportedProviderFeature:
      "Innloggingsmetoden eller plattformen støtter ikke denne funksjonen"
    }
  }
}

private enum BackendProfileError: Error {
  case identityMismatch
}
