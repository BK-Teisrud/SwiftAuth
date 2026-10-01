# Getting started

Configure one public OIDC client, restore its local session during startup, and create API clients only for the active session.

## Add the package

Add `https://github.com/BK-Teisrud/SwiftAuth.git` in Swift Package Manager and select `Auth`. Add `Networking` from SwiftNetworking when the application constructs `HTTPClient` directly.

Register the exact callback URI with the identity service and in the application. Custom schemes work on the minimum supported platforms. HTTPS callbacks require iOS 17.4 or macOS 14.4 or later plus Universal Links, Associated Domains, and a valid AASA file.

## Create the clients

```swift
import AuthenticationServices
import Auth
import Networking

@MainActor
func makeAuth(window: ASPresentationAnchor) async throws -> AuthClient {
    let configuration = try AuthConfiguration(
        issuer: URL(string: "https://login.example.com/")!,
        clientID: "registered-public-client-id",
        redirectURI: URL(string: "com.example.app://auth/callback")!,
        scopes: ["openid", "offline_access"],
        apiResource: .oauthResource(URL(string: "https://api.example.com")!),
        keychainNamespace: "com.example.app.production"
    )
    let browser = SystemAuthBrowser(presentationAnchor: { window })
    return try await AuthClient(configuration: configuration, browser: browser)
}
```

Keep one client for each configuration and share it across scenes. Construction acquires an exclusive process lock but does not read the Keychain. Call ``AuthClient/restoreSession()`` once during startup.

After a successful restore or login, create a fresh session-bound Networking stack:

```swift
let provider = AuthCredentialProvider(client: auth)
let api = HTTPClient(configuration: try ClientConfiguration(
    baseURL: URL(string: "https://api.example.com/")!,
    credentialProvider: provider
))
```

Do not reuse that provider after another successful restore or login. Cancel old account work and replace the API client when the session changes.

## Sign in and call the API

Start login only from an explicit user action:

```swift
try await auth.login(choice: .serviceSelection)

let metadata = try await api.execute(
    HTTPRequest(pathSegments: ["account"], requiresAuthentication: true)
)
```

API access never presents the browser. `requiresAuthentication` must be explicit for every protected request. Use ``AuthClient/state`` or ``AuthClient/states()`` for token-free state. On Apple platforms, ``AuthSessionObserver`` provides a thin Observation-compatible MainActor wrapper without UI.

## Continue

Read <doc:Configuration> before provider registration, <doc:SessionLifecycle> before building account switching, and <doc:NetworkingIntegration> before sending protected requests.

## Direct Apple and GitHub sign-in

For application-owned backend sessions, construct ``DirectAuthAdapter`` and pass it to `AuthClient(adapter:)`. Supply ``SystemAppleAuthorization``, ``SystemAuthBrowser`` and an application implementation of ``DirectAuthBackend``. Use explicit `.connection("apple")` or `.connection("github")` choices. See <doc:ProvidersAndExtensions> and `Docs/ProviderSetup.md` for an example and the backend contract. The backend must be implemented before this flow can be used in production.
