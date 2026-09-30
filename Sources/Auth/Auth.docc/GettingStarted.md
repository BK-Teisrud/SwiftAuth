# Kom i gang

Opprett én AuthClient, gjenopprett lokal sesjon og bind Networking til riktig innloggingssesjon.

## Installer pakken

Velg bibliotekproduktet `Auth` i appens Swift Package-avhengigheter. Lokal utvikling kan bruke mappen Auth i Xcode. Remote installasjon krever at Auth publiseres i et repository du har lesetilgang til; dokumentasjonen oppgir ikke en oppdiktet Auth-URL eller release-tag.

Auths Package.swift peker til den eksakte offentlige SwiftNetworking-releasen `0.3.0`. Hvis appen selv importerer Networking og oppretter HTTPClient, legg også Networking-produktet til app-targetet. Bruk samme godkjente dependency-versjon. Ingen GitHub-token er nødvendig for å hente avhengigheten.

## Før kodeopprettelse

Du trenger eksakt issuer, public/native client ID, registrert callback og én API-resource. `openid` må inngå i scopes. `offline_access` ber om refresh-støtte, men garanterer ikke at tjenesten utsteder refresh-token. Ingen client secret skal finnes i en native app.

Registrer callback-schemet i appens URL Types. For `com.company.app://auth/callback` er schemet `com.company.app`. Pakken registrerer ikke callbacks og leser ikke konfigurasjon automatisk fra Info.plist. HTTPS-callback krever også Associated Domains og AASA-oppsett, se <doc:Configuration>.

## Opprett delt klient

```swift
import Auth
import AuthenticationServices
import Foundation
import Networking

@MainActor
func makeAuth(window: ASPresentationAnchor) async throws -> AuthClient {
  let config = try AuthConfiguration(
    issuer: URL(string: "https://login.example.com/")!,
    clientID: "registered-native-client",
    redirectURI: URL(string: "com.company.app://auth/callback")!,
    apiResource: .oauthResource(URL(string: "https://api.example.com")!),
    postLogoutRedirectURI: URL(string: "com.company.app://auth/logout")!,
    keychainNamespace: "com.company.app.production"
  )
  let browser = SystemAuthBrowser(presentationAnchor: { window })
  return try await AuthClient(configuration: config, browser: browser)
}

func makeAPI(auth: AuthClient) throws -> HTTPClient {
  HTTPClient(configuration: try ClientConfiguration(
    baseURL: URL(string: "https://api.example.com/")!,
    credentialProvider: AuthCredentialProvider(client: auth)
  ))
}
```

URL-ene er plassholdere; de blir ikke kontaktet før appen eksplisitt starter en flyt. Velg `.auth0Audience` når tjenesten bruker audience i stedet for RFC 8707 resource. Begge er eksplisitte kontrakter, se <doc:Configuration>.

## Oppstart og innlogging

```swift
let auth = try await makeAuth(window: window)
try await auth.restoreSession()
var api = try makeAPI(auth: auth)

// Etter en eksplisitt brukerhandling:
try await auth.login()
api = try makeAPI(auth: auth)

let response = try await api.execute(
  HTTPRequest(pathSegments: ["protected"], requiresAuthentication: true)
)
```

`window` er appens aktive ASPresentationAnchor. Appen må eie klienten over tid og dele den mellom scener. Ikke opprett ny AuthClient etter hver login: samme lagringsidentitet kan bare ha én levende koordinator. Bytt API-klient/provider etter ny sesjon, ikke AuthClient.

`restoreSession()` leser bare lokal lagring. Det første beskyttede API-kallet kan derfor utløse nettverksrefresh. Håndter restore-feil før du bruker API-klienten; låst Keychain er ikke bevis på at brukeren er logget ut.

## Observer status

```swift
let stream = await auth.states()
for await state in stream {
  // Oppdater appens egen navigasjon og UI på riktig actor.
  // Ikke bruk lokal status som backendautorisasjon.
  _ = state
}
```

SwiftUI kan bruke `AuthSessionObserver(client:)` på MainActor. Behold observeren i appens modell; den kansellerer sin abonnement-task når den deinitialiseres. Streamen gir aktuell status umiddelbart og beholder bare siste verdi for trege konsumenter.

## Logg ut

Kall `try await auth.logout()` for lokal logout. Kanseller egne requests, koble ned realtime og tøm brukeravhengige data. Providerlogout er separat og skal ikke hindre lokal opprydding. Se <doc:SessionLifecycle>.

En kjørbar iOS/macOS-app med vindusregistrering, statusvisning, login, API-kall og logout finnes i `Examples/AuthExample`. Innlogging krever faktisk tjenestekonfigurasjon; kompilering alene verifiserer ikke providerintegrasjonen.
