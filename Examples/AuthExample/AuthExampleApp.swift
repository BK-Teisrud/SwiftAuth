import Auth
import AuthenticationServices
import Foundation
import Networking
import Observation
import SwiftUI

#if os(iOS)
  import UIKit
#else
  import AppKit
#endif

@main struct AuthExampleApp: App {
  @State private var model = ExampleSession()
  var body: some Scene {
    WindowGroup {
      VStack(alignment: .leading, spacing: 16) {
        Text("Auth example").font(.title)
        Text(model.status)
        if let observer = model.observer { Text(String(describing: observer.state)) }
        HStack {
          Button("Logg inn") { Task { await model.login() } }
          Button("Beskyttet API") { Task { await model.request() } }
        }.disabled(model.client == nil)
        HStack {
          Button("Gjenopprett") { Task { await model.restore() } }
          Button("Logg ut lokalt") { Task { await model.logout(provider: false) } }
          Button("Logg ut hos tjenesten") { Task { await model.logout(provider: true) } }
          Button("Avbryt") { Task { await model.client?.cancelLogin() } }
        }.disabled(model.client == nil)
        Text(
          "Sett AUTH_ISSUER, AUTH_CLIENT_ID, AUTH_RESOURCE og AUTH_API_URL i targetets Build Settings. Leverandørvalg konfigureres hos innloggingstjenesten."
        ).font(.caption)
      }
      .padding(24)
      .background(WindowProbe { window in Task { await model.start(window: window) } })
    }
  }
}

@MainActor @Observable final class ExampleSession {
  var status = "Venter på appvindu og konfigurasjon."
  var observer: AuthSessionObserver?
  var client: AuthClient?
  private var api: HTTPClient?
  private var started = false
  private var apiURL: URL?
  func start(window: ASPresentationAnchor) async {
    guard !started else { return }
    started = true
    do {
      func setting(_ key: String) throws -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
          !value.isEmpty, !value.contains("$(")
        else { throw AuthError.invalidConfiguration }
        return value
      }
      guard let issuer = URL(string: try setting("AUTH_ISSUER")),
        let resource = URL(string: try setting("AUTH_RESOURCE")),
        let apiURL = URL(string: try setting("AUTH_API_URL"))
      else { throw AuthError.invalidConfiguration }
      let configuration = try AuthConfiguration(
        issuer: issuer, clientID: setting("AUTH_CLIENT_ID"),
        redirectURI: URL(string: "com.teisrud.authexample://auth/callback")!,
        apiResource: .oauthResource(resource),
        postLogoutRedirectURI: URL(string: "com.teisrud.authexample://auth/logout")!,
        keychainNamespace: "com.teisrud.authexample.staging")
      let auth = try await AuthClient(
        configuration: configuration,
        browser: SystemAuthBrowser(presentationAnchor: { window }))
      client = auth
      observer = AuthSessionObserver(client: auth)
      self.apiURL = apiURL
      try await auth.restoreSession()
      try bindAPI()
      status = "Klar. Innlogging skjer i systemnettleseren."
    } catch { show(error) }
  }
  func login() async {
    do {
      try await client?.login()
      try bindAPI()
      status = "Innlogging fullført."
    } catch { show(error) }
  }
  func restore() async {
    do {
      try await client?.restoreSession()
      try bindAPI()
      status = "Lokal sesjon lest."
    } catch { show(error) }
  }
  func request() async {
    do {
      guard let api else { return }
      let response = try await api.execute(
        HTTPRequest(pathSegments: ["protected"], requiresAuthentication: true))
      status = "Beskyttet API svarte HTTP \(response.statusCode)."
    } catch { show(error) }
  }
  func logout(provider: Bool) async {
    guard let client else { return }
    var providerFailed = false
    if provider {
      do { try await client.logoutAtProvider() } catch { providerFailed = true }
    }
    do {
      try await client.logout()
      api = nil
      status =
        providerFailed
        ? "Lokal sesjon avsluttet. Utlogging hos tjenesten feilet." : "Lokal sesjon avsluttet."
    } catch { show(error) }
  }
  private func bindAPI() throws {
    guard let client, let apiURL else { return }
    api = HTTPClient(
      configuration: try ClientConfiguration(
        baseURL: apiURL,
        credentialProvider: AuthCredentialProvider(client: client)))
  }
  private func show(_ error: any Error) {
    // Never display raw provider errors, callbacks, token payloads or API bodies.
    if let safe = error as? AuthError {
      status = "Auth: \(safe)"
    } else {
      status = "Operasjonen feilet. Kontroller sesjonsstatus og tjenesteoppsett."
    }
  }
}

#if os(iOS)
  private struct WindowProbe: UIViewRepresentable {
    let found: @MainActor (UIWindow) -> Void
    func makeUIView(context: Context) -> ProbeView { ProbeView(found: found) }
    func updateUIView(_ uiView: ProbeView, context: Context) {}
    final class ProbeView: UIView {
      let found: @MainActor (UIWindow) -> Void
      init(found: @escaping @MainActor (UIWindow) -> Void) {
        self.found = found
        super.init(frame: .zero)
      }
      required init?(coder: NSCoder) { nil }
      override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window { found(window) }
      }
    }
  }
#else
  private struct WindowProbe: NSViewRepresentable {
    let found: @MainActor (NSWindow) -> Void
    func makeNSView(context: Context) -> ProbeView { ProbeView(found: found) }
    func updateNSView(_ nsView: ProbeView, context: Context) {}
    final class ProbeView: NSView {
      let found: @MainActor (NSWindow) -> Void
      init(found: @escaping @MainActor (NSWindow) -> Void) {
        self.found = found
        super.init(frame: .zero)
      }
      required init?(coder: NSCoder) { nil }
      override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { found(window) }
      }
    }
  }
#endif
