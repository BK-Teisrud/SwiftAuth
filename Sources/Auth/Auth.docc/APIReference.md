# Samlet API-referanse

Alle public typer, medlemmer, signaturer og standardverdier i Auth.

## Sesjonsklient

```swift
public actor AuthClient {
  public init(configuration: AuthConfiguration, browser: any AuthBrowserSession) async throws
  public init(adapter: any AuthOIDCAdapter) async throws
  public private(set) var state: AuthState
  public func states() -> AsyncStream<AuthState>
  public func restoreSession() throws
  public func login(choice: AuthLoginChoice = .serviceSelection) async throws
  public func cancelLogin() async
  public func validAccessToken() async throws -> String
  public func recover(rejectedToken: String) async throws -> String
  public func logout() async throws
  public func logoutAtProvider() async throws
}
```

Signaturblokkene er API-oversikter uten implementasjonskropper, ikke komplette Swift-filer. Synkrone actor-metoder/getters krever await fra andre actors: `try await auth.restoreSession()`, `await auth.states()`, `await auth.state`. Ingen public setter tillater appen å tildele sesjonsstatus. Initializere tar en levetidslease; de starter ikke nettverk. Detaljer: <doc:SessionLifecycle>.

## Konfigurasjon og valg

AuthConfiguration har public immutable properties issuer: URL, clientID: String, redirectURI: URL, refreshTimeout: TimeInterval, scopes: [String], apiResource: AuthAPIResource, postLogoutRedirectURI: URL?, keychainNamespace: String, loginChoices: [AuthLoginChoice], ephemeralBrowserSession: Bool, trustedEndpointOrigins: [URL], trustedIDTokenAudiences: [String]. Den er Sendable og Equatable.

```swift
public init(
  issuer: URL, clientID: String, redirectURI: URL,
  scopes: [String] = ["openid", "offline_access"], apiResource: AuthAPIResource,
  postLogoutRedirectURI: URL? = nil, keychainNamespace: String,
  loginChoices: [AuthLoginChoice] = [.serviceSelection], ephemeralBrowserSession: Bool = false,
  trustedEndpointOrigins: [URL] = [], trustedIDTokenAudiences: [String] = [],
  refreshTimeout: TimeInterval = 60
) throws
```

AuthLoginChoice: `.serviceSelection`, `.connection(String)`, Sendable/Equatable. AuthAPIResource: `.auth0Audience(String)`, `.oauthResource(URL)`, Sendable/Equatable. Validering og wire-parametere: <doc:Configuration>.

## Identitet og state

AuthIdentity er Sendable/Equatable/Codable med immutable issuer: String og subject: String, opprettet med `init(issuer:subject:)`. Initializeren i seg selv verifiserer ikke en identitet; adapteren gjør det. Bruk begge felter som konto-ID, ikke e-post.

AuthState er Sendable/Equatable: `.restoring`, `.signedOut(problem: AuthError? = nil)`, `.signingIn`, `.signedIn(AuthIdentity, problem: AuthError? = nil)`, `.reauthenticationRequired(AuthIdentity?, reason: AuthError)`. Ingen tokens er del av status. Tilstandsbetydning: <doc:SessionLifecycle>.

AuthSessionObserver er MainActor/Observable, opprettes med `init(client: AuthClient)` og har public read-only `state: AuthState`, initialt restoring. Den eier abonnementet og kansellerer det ved deinit. UI/navigasjon eies av appen.

## Networking-provider

AuthCredentialProvider er actor som implementerer Networking.CredentialProvider:

```swift
public init(client: AuthClient)
public func bearerToken() async throws -> String
public func recover(rejectedToken: String) async throws -> String
```

Den starter aldri interaktiv login. Binding skjer ved første vellykkede bearerToken-kall; recovery før dette eller etter sesjonsbytte gir operationInvalidated. Samtidighet/ny klient etter login: <doc:NetworkingIntegration>.

## Browsergrense

AuthBrowserSession er MainActor/AnyObject/Sendable:

```swift
func authenticate(url: URL, callbackURI: URL, ephemeral: Bool) async throws -> URL
func cancel()
```

Implementasjonen returnerer callbackadresse, ikke verifiserte tokens. Den må bruke systembrowser, håndtere cancellation og ikke bruke embedded WKWebView. Bruk egen browser per uavhengig klient.

SystemAuthBrowser er MainActor-final NSObject og ASWebAuthenticationPresentationContextProviding, med public:

```swift
init(presentationAnchor: @escaping @MainActor @Sendable () -> ASPresentationAnchor)
func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor
func authenticate(url: URL, callbackURI: URL, ephemeral: Bool) async throws -> URL
func cancel()
```

Anchor-closure skal returnere appens gyldige aktive vindu. En browserinstans tillater én operasjon. HTTPS callback har OS-grense beskrevet i <doc:Configuration>. cancel() stopper browserinstansen; den sletter ikke Keychain eller appens lokale sesjon.

## Adaptergrense

AuthOIDCAdapter er MainActor/Sendable, med read-only configuration: AuthConfiguration og:

```swift
func login(choice: AuthLoginChoice) async throws -> AuthTokenResponse
func cancelLogin() async
func prepareRefresh() async throws
func refresh(token: String, identity: AuthIdentity, nonce: String?, binding: AuthIDTokenBinding?) async throws -> AuthTokenResponse
func logoutAtProvider() async throws
```

prepareRefresh har default no-op. Protocol-login har ingen default choice; AuthClient og NativeOIDCAdapter har egne deklarasjoner. Protocol-refresh krever nonce/binding som argumenter, også når de er nil.

NativeOIDCAdapter er MainActor-final og implementerer dette med public configuration og:

```swift
init(
  configuration: AuthConfiguration, browser: any AuthBrowserSession,
  transport: any HTTPTransport = URLSessionTransport(),
  now: @escaping @Sendable () -> Date = { Date() }
)
func login(choice: AuthLoginChoice) async throws -> AuthTokenResponse
func cancelLogin()
func prepareRefresh() async throws
func refresh(token: String, identity: AuthIdentity, nonce: String? = nil, binding: AuthIDTokenBinding? = nil) async throws -> AuthTokenResponse
func logoutAtProvider() async throws
```

Native cancelLogin er synkront MainActor-isolert, selv om protocolkravet er async. Bruk normalt AuthClient som lifecyclekoordinator; direkte adapterbruk gir ikke lease, varig quarantine eller Keychain-commit. Utvidelseskrav: <doc:ProvidersAndExtensions>.

## Sensitive adapterverdier

AuthTokenResponse er Sendable og CustomStringConvertible/CustomDebugStringConvertible. Public immutable properties: identity: AuthIdentity, accessToken: String, expiresAt: Date, refreshToken: String?, loginNonce: String?, idTokenBinding: AuthIDTokenBinding?. Initializer:

```swift
init(identity: AuthIdentity, accessToken: String, expiresAt: Date, refreshToken: String?, loginNonce: String? = nil, idTokenBinding: AuthIDTokenBinding? = nil)
```

`description` og `debugDescription` er begge `AuthTokenResponse(<REDACTED>)`. Feltene inneholder likevel ekte credentials; redigert beskrivelse gjør dem ikke trygge å sende til analytics eller lagre manuelt. Initializeren utfører ikke OIDC-validering.

AuthIDTokenBinding er Codable/Sendable/Equatable, med immutable audiences: [String] og authenticationTime: Double?. `init(audiences: [String], authenticationTime: Double? = nil)` sorterer audiences. Den verifiserer ikke claims; adapteren må opprette den fra verifiserte claims.

## Feil

AuthError er Error/Sendable/Equatable. Alle 20 cases og foreslått handling er dokumentert i <doc:ErrorsAndRecovery>. Public computed `recoveryAction: AuthRecoveryAction` returnerer én av `.retry`, `.signIn`, `.configure`, `.waitForStorage`, `.none`. Handling er veiledning, ikke automatisk recovery. AuthRecoveryAction er Sendable/Equatable.

## Interne typer

StoredSession, SessionStorage, KeychainSessionStorage, SessionContext, SessionLease, SessionFiles, AsyncResultGate, awaitShared, OIDCService, OIDCMetadata, OIDCTokenResponse, OIDCCallbackValidator, IDTokenValidator, VerifiedIDToken, OIDCEncoding og StrictJSON er interne, ikke støttede app-API-er. Fil-/vedlikeholdsansvar: <doc:Architecture>.
