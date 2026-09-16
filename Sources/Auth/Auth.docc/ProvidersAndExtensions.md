# Innloggingsmetoder og nye adaptere

Utvid gjennom registrerte hosted connections eller en fullt validerende OIDC-adapter.

## Apple, Vipps og OTP

Pakken viser tjenestens hosted login i ASWebAuthenticationSession. Den inneholder ingen direkte Apple/Vipps-SDK, SMS-sender eller e-postleverandør. Ingen passord/koder samles inn i appen.

| Metode | Nødvendig oppsett | Auth-valg |
| --- | --- | --- |
| Apple | Apple-registrering og brokerens Apple-integrasjon | serviceSelection eller registrert connection |
| Vipps | Leverandøravtale/registrering og faktisk brokerintegrasjon | Bare et navn som brokeren faktisk har konfigurert |
| E-post OTP | Tjenestens levering, kodekontroll og rate limiting | Registrert e-post-connection |
| SMS OTP | Tjenestens SMS-leverandør, kodekontroll og misbruksvern | Registrert SMS-connection |

```swift
let choices: [AuthLoginChoice] = [
  .serviceSelection,
  .connection("registered-apple-connection"),
  .connection("registered-email-connection"),
  .connection("registered-sms-connection")
]
```

Connection-navn er plassholdere, ikke universelle standardverdier. Et Vipps-navn aktiverer ingen integration eller avtale. Tjenesten eier kodeutløp, engangsbruk, anti-enumeration, begrensning av forsøk, kontolinking og upstream-identitet. Det er ikke verifisert live støtte for noen av disse metodene i repositoryet.

## Krav til medfølgende native adapter

Tjenesten må støtte code, PKCE S256, discovery og RS256-signerte ID-tokens, offentlige klienter uten secret og valgt resource-parameter. Native adapter sender ingen vilkårlige authorize-parametere og støtter ikke implicit/password/device grants, PAR, DPoP eller egne UI-er. En provider som trenger slike kontrakter er ikke automatisk kompatibel.

Discovery bygger `.well-known/openid-configuration` under konfigurert issuer-path. Issuer fra metadata/token må matche konfigurasjonen eksakt. Endepunkter må følge origin-policyen i <doc:Configuration>.

## AuthOIDCAdapter-kontrakten

Protocol er MainActor-isolert og Sendable. Den er en betrodd sikkerhetsgrense: AuthClient koordinerer lagring og generasjon, men utfører ikke adapterens kryptografiske validering på nytt.

| Medlem | Implementasjonens ansvar |
| --- | --- |
| configuration | Immutable og korrekt for issuer/client/resource som returnerte tokens tilhører. |
| login(choice:) | Systembrowser, PKCE/state/nonce, callback og komplett signatur/claimkontroll før retur. |
| cancelLogin() | Stopp egen browseroperasjon; sent callback må ikke installere noe. |
| prepareRefresh() | Avklar forutsetninger uten å sende refresh-credential. Default er no-op; override ved nettverksforutsetninger. |
| refresh(token:identity:nonce:binding:) | Én refresh-request, identitetsbinding, eventuell ID-tokenvalidering og riktig usikkerhetsklassifisering. |
| logoutAtProvider() | Separat providerlogout; kast unsupportedProviderFeature hvis ikke støttet. Lokal logout eies fortsatt av AuthClient. |

Returner AuthTokenResponse med access-token, faktisk utløp, verifisert issuer/subject og eventuell refresh-token. Ved login skal original nonce og verifisert audience/auth_time-binding returneres når ID-token brukes. De må kontrolleres igjen ved refresh/restart. En legitimt manglende refresh-erstatning representeres som nil; tom streng er ikke en erstatning.

Kode som bare dekoder JWT-payload er ikke en adapterimplementasjon. Bruk Security/CryptoKit til kryptografiske primitiver, ikke egen RSA/SHA-implementasjon. Ikke stol på algoritme eller ekstern nøkkel-URL fra tokenet.

## Cancellation og usikkert utfall

Adapteren må samarbeide med Task-cancellation og sjekke cancellation før credential-send og før resultat retur. Kjernen ignorerer sene resultater etter frist/operasjonsbytte, men kan ikke tvangsavslutte en tredjeparts async-implementasjon som aldri returnerer.

Et definitivt avvist refresh-grant gir refreshRejected. Tapt respons/transportfeil etter mulig sending gir refreshOutcomeUnknown. Ikke maskér det som retrybar discovery-feil, og ikke retry roterende refresh-requests i adapteren.

## Injiser browser og transport

NativeOIDCAdapter kan opprettes med en AuthBrowserSession, HTTPTransport og Sendable klokke-closure. Dette gjør fixturetester mulig uten reelle tjenester. Hver uavhengig klient bør ha egen browserinstans; SystemAuthBrowser støtter én browseroperasjon og cancellation gjelder den instansen.

```swift
@MainActor
func makeCustomTransportClient(
  config: AuthConfiguration,
  browser: any AuthBrowserSession,
  transport: any HTTPTransport
) async throws -> AuthClient {
  let adapter = NativeOIDCAdapter(
    configuration: config, browser: browser, transport: transport
  )
  return try await AuthClient(adapter: adapter)
}
```

Snippetet forutsetter import Auth og Networking. Transport må respektere HTTPS/tillitspolicy, reject-redirects, maksimal responsstørrelse og ingen credential-cache. Klokken skal være stabil og realistisk; biblioteket har ingen clock skew/leeway.

## Valider en ny adapter

Test faktiske signaturer, feil issuer/sub/aud/azp/nonce/utløp, callbackstate, duplikate felter, roterte keys og begge refreshvarianter med/uten ID-token. Test requesten på wire-nivå, ikke bare et mock-resultat. Gjennomfør deretter live staging med registrerte callbacks og faktisk beskyttet API. Se <doc:TestingAndRelease>.
