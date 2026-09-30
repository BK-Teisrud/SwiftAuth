# Auth

Swift-pakke for passordfri OIDC-innlogging, sikker lokal sesjon og API-credentials. Versjon 0.1.0. Swift 6.0+, iOS 17+, macOS 14+. Ett bibliotekprodukt, ett hovedtarget og ett testtarget. Ingen DesignSystem-avhengighet, ferdige skjermer eller navigasjon.

**Innloggingstjenesten eier Apple, Vipps og e-post/SMS-engangskoder.** Appen er en offentlig OIDC-klient. Den samler ikke inn passord eller engangskoder, og har ingen klienthemmelighet. AuthenticationServices viser tjenestens innlogging i systemnettleseren.

## Komplett dokumentasjon

Start i [dokumentasjonsoversikten](Docs/README.md). Den komplette [DocC-katalogen](Sources/Auth/Auth.docc/Auth.md) kan bygges i Xcode, og public API har kildekommentarer for Quick Help.

- [Kom i gang](Sources/Auth/Auth.docc/GettingStarted.md) og [alle konfigurasjonsvalg](Sources/Auth/Auth.docc/Configuration.md).
- [Sesjon, refresh og logout](Sources/Auth/Auth.docc/SessionLifecycle.md), [Networking-integrasjon og bruksområder](Sources/Auth/Auth.docc/NetworkingIntegration.md).
- [Apple/Vipps/OTP og nye adaptere](Sources/Auth/Auth.docc/ProvidersAndExtensions.md), [alle feil og recovery](Sources/Auth/Auth.docc/ErrorsAndRecovery.md).
- [Sikkerhet og lagring](Sources/Auth/Auth.docc/Security.md), [alle produksjonsfiler og arkitektur](Sources/Auth/Auth.docc/Architecture.md).
- [Samlet API-referanse](Sources/Auth/Auth.docc/APIReference.md), [testing, DocC-bygg og release](Sources/Auth/Auth.docc/TestingAndRelease.md).

## Implementasjon og faktisk status

Sesjonskjernen er generisk gjennom `AuthOIDCAdapter`. Medfølgende `NativeOIDCAdapter` implementerer Authorization Code med PKCE S256 og discovery, med Foundation, AuthenticationServices, Security og CryptoKit. **Eneste pakkeavhengighet er vår egen Networking.** Ingen Auth0.swift, JWTDecode eller SimpleKeychain brukes.

Tilfeldig PKCE-verifier, state og nonce lages med SecRandomCopyBytes. S256 og access-token-hash bruker CryptoKit. RSA-signaturer verifiseres med SecKeyVerifySignature; vi implementerer ikke kryptografiske primitiver. Protokoll- og JSON/JWS-kontrollene vedlikeholdes i Auth. Implementasjonen følger [OIDC Core](https://openid.net/specs/openid-connect-core-1_0.html) og [PKCE RFC 7636](https://www.rfc-editor.org/rfc/rfc7636).

Første versjon tillater RS256 og RSA-nøkler på 2048–8192 bit. Den avviser andre algoritmer, usignerte tokens, ukjente/ambivalente key IDs, privat nøkkelmateriale i valgt JWK, kritiske JWS-utvidelser og dupliserte JSON-nøkler. Issuer, subject, audience, azp (også ved enkel audience når azp finnes), exp, iat, valgfri nbf, login-nonce og valgfri at_hash kontrolleres. Ingen rå ID-token-identitet brukes før signatur og claims er validert. Ingen klokkeleeway er aktivert.

Discovery krever code, S256 og RS256. Endepunktene må bruke HTTPS, uten credentials eller fragment. Issuers origin er tillatt som standard; andre origins må registreres eksplisitt i `trustedEndpointOrigins`. Statiske endpoint-queryparametere bevares; parametere som kolliderer med autentiseringsfelter avvises. API-resource støtter eksplisitt Auth0-audience eller RFC 8707 resource-parameter. `connection` er et eksplisitt leverandørvalg, ikke en standard OAuth-parameter. Andre parameterkontrakter krever en egen adapter. Providerlogout krever publisert end_session_endpoint og registrert post_logout_redirect_uri. Adapteren sender et verifisert ID-token som id_token_hint når det finnes i minnet; ellers må tjenesten støtte client_id uten hint. ID-token lagres aldri på disk. Kjør providerlogout før lokal logout dersom tjenesten krever hint. Enkelt-JWT-er begrenses til 64 KiB; hele tokenresponsen og discovery begrenses også til 64 KiB, og JWKS til 256 KiB; expires_in må være positiv og høyst ett år.

**Ingen live leverandørintegrasjon er verifisert ennå.** Testene bruker syntetiske RSA-signerte tokens og den faktiske Apple-baserte valideringen. Dette erstatter ikke Apple/Vipps/OTP og beskyttet API på simulator og fysisk enhet. [Oppsett og integrasjonstest](Docs/ProviderSetup.md) beskriver releasekravene. Auths kode tilhører Teisrud Development AS; se LICENSE.

## Installasjon

Legg til `https://github.com/BK-Teisrud/SwiftAuth.git` i Swift Package Manager og velg produktet `Auth`. Hvis appen skal opprette HTTPClient direkte, velg også Networking-produktet fra SwiftNetworking som appavhengighet; eksempelappen viser begge produktreferansene. Auth 0.1.0 bruker den eksakte publiserte Networking-releasen `0.3.0` fra [SwiftNetworking](https://github.com/BK-Teisrud/SwiftNetworking). Ingen lokal nabomappe eller flytende branch kreves.
Networking-repositoryet er offentlig og kan løses av SwiftPM uten credentials. Ingen GitHub-token skal bygges inn i Package.swift, package-URL-er, appen eller CI-konfigurasjonen.

Ingen konfigurasjon leses automatisk fra appens Info.plist. Appen må likevel registrere callback-schemet i sitt eget URL Types-oppsett.

## To apper med isolerte konfigurasjoner

```swift
import Foundation
import AuthenticationServices
import Auth
import Networking

@MainActor
func makeClients(window: ASPresentationAnchor) async throws -> (AuthClient, HTTPClient) {
  let configuration = try AuthConfiguration(
    issuer: URL(string: "https://example.eu.auth0.com/")!,
    clientID: "registered-app-one-client-id",
    redirectURI: URL(string: "com.teisrud.appone://auth/callback")!,
    scopes: ["openid", "offline_access"],
    apiResource: .auth0Audience("https://api-one.example.com"),
    postLogoutRedirectURI: URL(string: "com.teisrud.appone://auth/logout")!,
    keychainNamespace: "com.teisrud.appone.production",
    loginChoices: [.serviceSelection, .connection("apple"), .connection("email"), .connection("sms")]
  )
  let browser = SystemAuthBrowser(presentationAnchor: { window })
  let auth = try await AuthClient(configuration: configuration, browser: browser)
  let api = HTTPClient(configuration: try ClientConfiguration(
    baseURL: URL(string: "https://api-one.example.com/")!,
    credentialProvider: AuthCredentialProvider(client: auth)
  ))
  return (auth, api)
}

let appTwoConfiguration = try AuthConfiguration(
  issuer: URL(string: "https://other-example.eu.auth0.com/")!,
  clientID: "registered-app-two-client-id",
  redirectURI: URL(string: "com.teisrud.apptwo://auth/callback")!,
  apiResource: .auth0Audience("https://api-two.example.com"),
  keychainNamespace: "com.teisrud.apptwo.production"
)
```

URL-er, client IDs og connection-navn er eksempler. Bruk nøyaktig registrerte verdier. Vipps kan legges til som `.connection("actual-vipps-connection")` **etter** at brokerintegrasjonen er etablert og testet. Navnet aktiverer ingen leverandørintegrasjon av seg selv. Namespace må inkludere app og miljø; lag separat konfigurasjon for staging og produksjon.

## Offentlig API og livssyklus

| API | Kontrakt |
| --- | --- |
| `restoreSession()` | Leser lokal identitet/refresh-token fra Keychain. Ingen browser og ingen nettverksrefresh før token etterspørres. |
| `login(choice:)` | Eksplisitt interaktiv login. Et nytt kall på samme klient avvises med loginAlreadyInProgress. |
| `cancelLogin()` | Invaliderer operasjonen; sent callback-resultat kan ikke publisere innlogging. |
| `validAccessToken()` | Fornyer med margin på 10 % av gjenværende levetid ved installasjon, høyst 60 sekunder, når refresh finnes; uten refresh returneres tokenet frem til faktisk utløp. |
| `recover(rejectedToken:)` | Gjenbruker nyere token fra samme sesjon ved forsinket 401; ukjente tokens avvises. |
| `logout()` | Invaliderer operasjoner, tømmer minne, sletter Keychain og publiserer signedOut. Slettefeil kastes eksplisitt. |
| `logoutAtProvider()` | Separat, valgfri browserlogout hos tjenesten; krever registrert post-logout URI. |
| `state` / `states()` | Tokensfri status; streamen har én bufret siste tilstand. |
| `AuthSessionObserver` | Tynt MainActor/Observation-lag for SwiftUI. Ingen skjermer eller navigasjon. |

Start én klient per appkonfigurasjon og kall restore ved oppstart. Offentlige initializere er `async throws`: en prosessregistrering og eksklusiv fil-lås avviser en ny klient for samme lagringsidentitet med `sessionAlreadyInUse`. Låsen frigjøres når klienten deinitialiseres eller prosessen avsluttes. Del klienten mellom scener; ikke lag én per vindu. App Extensions og delte Keychain access groups støttes ikke. `signedIn` betyr lokal sesjon, ikke at Go-serveren har bekreftet alle rettigheter. Identiteten er issuer + subject. Ingen profil/e-post brukes som primærnøkkel.

Beskyttede Networking-requests må eksplisitt ha `requiresAuthentication: true`:

```swift
let response = try await api.execute(
  HTTPRequest(pathSegments: ["protected"], requiresAuthentication: true)
)
```

Appen starter login etter brukerens eksplisitte handling. `.connection("email")` og `.connection("sms")` sender valget til tjenesten; appen verken sender eller lagrer koder. Innlogging gjennom API-kall starter aldri browser. Bind adapteren bare til riktig API-klient. ID-token sendes aldri som bearer; access token behandles som opaque credential.

Networking pakker providerfeil inn i sin egen AuthenticationError. Observer derfor AuthState for den strukturerte Auth-årsaken og behov for ny innlogging; direkte adapter-/AuthClient-kall kaster AuthError. Appen eier feilmeldinger, cacheopprydding ved kontobytte og navigasjon.

AuthCredentialProvider er en actor som binder seg til sesjonen ved første vellykkede bearerToken-kall. Etter vellykket login, restore eller logout er en tidligere bundet provider ugyldig, også når samme bruker logger inn igjen eller tjenesten returnerer samme tokenverdi. Opprett en ny provider og HTTPClient etter vellykket login/restore; eksempelappen gjør dette. Mislykket eller avbrutt login endrer ikke sesjonsbindingen. Tokenrotasjon innen samme sesjon beholder bindingen. Del provider mellom API-klienter bare når de tilhører samme sesjon og riktig API.

En forsinket 401 fra en gammel API-klient avvises med operationInvalidated gjennom Networking sin providerFailure. Forespørselen sendes aldri på nytt med credentials fra en senere sesjon. Direkte recover-kall godtar bare tokens som klienten faktisk har utlevert; høyst 256 SHA-256-fingeravtrykk beholdes, og eldre rejections kan derfor avvises. Fingeravtrykk lagres ikke på disk. Appen må fortsatt kansellere gamle requests og forkaste gamle responses ved logout/kontobytte: pakken tilbakekaller ikke allerede sendte requests eller serverutstedte tokens.

Én interaktiv operasjon per NativeOIDCAdapter er tillatt. Det finnes ingen global SDK-transaksjon. En delt SystemAuthBrowser støtter kun én browseroperasjon; gi separate klienter egne browserinstanser.

## Keychain og refresh

Refresh-token og minimal identitet lagres som ett Keychain-element. Access-/ID-token lagres ikke varig. Namespace er en SHA-256-hash av entydig kodet app/miljø-namespace, issuer, client ID og API-resource. Standard er WhenUnlockedThisDeviceOnly, ingen iCloud-synkronisering eller shared access groups. Keychain-data kan overleve avinstallering.

Keychain-funksjonene er synkrone for å hindre actor-reentrancy mellom generasjonskontroll og lagringscommit. Security-feil beholder OSStatus i AuthError. Midlertidig låst/utilgjengelig Keychain betyr ikke manglende sesjon.

Én delt refresh-task brukes per sesjon. refreshTimeout i AuthConfiguration setter en samlet tidsfrist for forberedelse/discovery, tokenutveksling og JWKS/validering; standard er 60 sekunder (positiv og høyst 3600). Fristen gjelder ikke brukerens tid i innloggingsnettleseren. Timeout før refresh-credential kan være sendt gir networkUnavailable og tillater nytt forsøk. Etter mulig sending gir timeout refreshOutcomeUnknown og varig karantene. Sene resultater installeres ikke, også når en injisert adapter ignorerer cancellation. Cancellation av én ventende tokenforespørsel returnerer CancellationError uten å kansellere den delte refresh-tasken som andre kall bruker; logout og ny login invaliderer hele operasjonen. Nytt refresh-token lagres før access token publiseres; et legitimt manglende erstatningstoken beholder det gamle. En varig refresh-in-flight-markering lagres **før** tokenrequesten. Discovery og øvrige forutsetninger avklares før markeringen lagres. Feil før sending endrer ikke credential-karantenen og kan forsøkes igjen. Hvis appen avsluttes etter markering, en respons går tapt eller lagring etter rotasjon feiler, kan denne markeringen ikke automatisk nullstilles ved restore. Pakken bevarer credentials og lokal identitet, men blokkerer blind retry. Brukeren må starte en ny interaktiv login. Dette er en konservativ førstegangs-policy, ikke automatisk recovery av roterende tokens.

Refresh-ID-token kan mangle; hvis det finnes, valideres det. En eventuell refresh-nonce krever kjent original login-nonce. Original login-nonce, original audience og eventuell auth_time lagres sammen med minimal sesjonsinformasjon i Keychain, og kontrolleres også etter prosessrestart. Et refresh-ID-token må bevare original audience og, dersom auth_time returneres, eventuell opprinnelig autentiseringstid. Eldre lagrede sesjoner uten audience-binding krever ny login hvis refresh inneholder ID-token.

invalid_grant krever ny login, også etter restore når avvisningen ble lagret. Timeout/ukjent utfall uttrykkes som signedIn med refreshOutcomeUnknown; identiteten beholdes, mens credentials ikke brukes videre. Utløpte tokens returneres aldri. Sesjonsgenerasjon beskytter mot gamle login-/refresh-resultater etter logout eller kontobytte.

Dersom Keychain-sletting feiler, er minnet tømt og status signedOut med eksplisitt feil, men diskcredentials kan fortsatt finnes. Før sletting skrives en atomisk, credential-fri logout-markør i Application Support. Markøren blokkerer ny login og gjør at en ny klient/prosess må fullføre Keychain-sletting før restore. Etter vellykket sletting fjernes markøren. Appen må håndtere feil og forsøke igjen når lagring er tilgjengelig. Credential-sletting forsøkes også hvis markøren ikke kan skrives. Hvis både markørlagring og sletting feiler, returneres logoutPersistenceUnavailable; ingen løsning kan love varig logout når begge lagringsmekanismene er utilgjengelige. Lokal status og minne tømmes likevel.

## Utvidelse og avgrensninger

Nye innloggingsmetoder hos samme broker legges til som registrerte connections i konfigurasjonen. Bytte av OIDC-tjeneste skjer gjennom en ny AuthOIDCAdapter, opprettet med `AuthClient(adapter:)`. Adapteren må bruke offisielle/Apple-kryptografiske API-er og faktisk verifisere alle protokollkontrollene. AuthTokenResponse er en sensitiv adaptergrense med redigert beskrivelse; den inngår aldri i offentlig sesjonsstatus. `.oauthResource` sender RFC 8707 resource eksplisitt; tjenesten må støtte dette oppsettet.

Ingen direkte Apple/Vipps SDK, passordgrant, SMS/e-postleverandør, konto-linking, roller, backendvalidering, kryptert database, multi-resource tokenutveksling eller automatisk deling mellom apper. Providerlogout kan påvirke brokerens nettlesersesjon, men lover ikke logout fra Apple/Vipps eller andre apper. Tokenrevokering er ikke inkludert i denne versjonen; lokal logout avhenger aldri av en revokeringsrequest.

Diagnostikklogger er ikke aktivert. Feilene inneholder ingen interne nettverks-/valideringstekster, URL, authorization code, PKCE, tokens eller personopplysninger. Appen skal heller ikke legge slike verdier i analytics eller crash metadata.

## Verifikasjon

```sh
swift test
xcrun swift-format lint --strict --recursive Package.swift Sources Tests
```

Session-testene injiserer adapter, lagring og klokke. Sikkerhetstestene bruker den faktiske NativeOIDCAdapter/Apple Security, syntetiske RSA-signerte tokens, injisert nettverk og browsergrensen. Testsignering finnes kun i testtargetet. Testene kontakter ingen leverandørtjeneste. Integrasjon med faktiske tjenester og fysisk enhet er et separat releasekrav i ProviderSetup.md.

## Drift og integrasjon

Discovery og JWKS caches i høyst fem minutter. Ukjent key ID oppdaterer JWKS én gang per valideringskall; selve tokenrequesten gjentas aldri. Nye nøkler valideres med samme algoritme- og claimregler. Kun RS256 støttes; legg til andre algoritmer først etter egne signaturtester og en konkret tjenestekontrakt.

Custom-scheme callbacks støttes på iOS 17/macOS 14. HTTPS-callbacks bruker Apples nye callback-API på iOS 17.4/macOS 14.4 eller nyere; konfigurasjonen avvises på eldre OS. Appen må konfigurere Associated Domains og nettstedets AASA-fil for HTTPS, og eksakt host/path må være registrert hos tjenesten.

`AuthError.recoveryAction` foreslår apphandling: retry, signIn, configure, waitForStorage eller none. Dette er UI-veiledning; det omgår aldri klientens refresh-karantene. Før-send nettverksfeil uttrykkes som networkUnavailable, HTTP 5xx som serviceUnavailable og avvisning ved første tokenutveksling som providerRejected. Etter mulig refresh-sending behandles transportfeil konservativt som refreshOutcomeUnknown. En signert, men ugyldig refresh-ID-token gir ny autentisering, ikke gjentatt tokenrequest.

En kjørbar iOS/macOS-app finnes i [Examples/AuthExample](Examples/AuthExample/README.md). [Releaseveiledningen](Docs/Release.md) beskriver versjonering, backendkontrakt og live verifikasjon. Ingen leverandøravtaler, secrets eller produksjonstjenester er opprettet av pakken.

Keychain bruker eksplisitt Apples Data Protection Keychain på macOS, slik at accessible-attributtet faktisk gjelder også der. Apper må signeres med korrekt application identifier og Keychain-entitlements; eksempelappen viser dette oppsettet. Gamle development-credentials i legacy macOS-Keychain migreres ikke automatisk; bruk ny login. Reelle Keychain-integrasjonstester kjøres i den signerte eksempelappverten på begge plattformer, ikke den generiske Swift Package-testverten.

ID-token må inneholde client ID som audience. Andre audiences avvises som standard; registrer bare faktisk betrodde ekstra ID-token-audiences i trustedIDTokenAudiences. Denne tillitslisten gjelder ID-token, ikke API-resource. Selv en betrodd ekstra audience kan ikke legges til eller fjernes under refresh: det opprinnelige audience-settet er fortsatt bundet til sesjonen.

## Intern struktur

AuthClient eier sesjonslivssyklus og varige commits. SessionContext samler identitet, credentials, refresh-binding og beregning av tilbakeført AuthState. Operasjonsgenerasjon beskytter pågående arbeid; en separat sesjons-ID beskytter API-klienter gjennom kontobytte. Feilet/avbrutt gjeninnlogging beholder reauthenticationRequired når den gamle sesjonen ikke kan brukes.

NativeOIDCAdapter eier browseroperasjoner og PKCE. OIDCCallbackValidator kontrollerer callbacks uavhengig av presentasjon. OIDCService er en egen actor for discovery, endpoint-tillit, JWKS-cache, tokenutveksling og protokollvalidering utenfor MainActor. IDTokenValidator returnerer identitet og original claim-binding fra én signatur-/claimvalidering; adapteren parser ikke verifiserte claims på nytt. SystemAuthBrowser og AuthSessionObserver forblir på MainActor.

Denne utviklingsversjonen endrer AuthCredentialProvider fra struct til actor og gjør providerens levetid sesjonsbundet. Oppdater appenes API-klientopprettelse før oppgradering; ikke gjenbruk tidligere bundne providers etter ny login/restore.

## Repository og GitHub

Gjeldende offentlige API er versjonert som 0.1.0. Før 1.0 kan minorversjoner inneholde kildekodebrytende endringer i tråd med Semantic Versioning. En publisert pakkeversjon er ikke dokumentasjon på at en bestemt provider-, broker- eller backendintegrasjon er produksjonsgodkjent.

Se [GitHub-oppsett](Docs/GitHubSetup.md) for repository- og CI-konfigurasjon, [bidragsveiledning](CONTRIBUTING.md) for vedlikehold og [sikkerhetsrutinen](SECURITY.md) for privat rapportering. Copyright © 2026 Teisrud Development AS. Alle rettigheter forbeholdt; se [LICENSE](LICENSE).
