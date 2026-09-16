# ``Auth``

Passordfri OIDC-innlogging, sikker lokal sesjon og sesjonsbundne API-credentials for Swift-apper.

Auth har ett bibliotekprodukt og støtter Swift 6.0+, iOS 17+ og macOS 14+. Pakken bruker Apple-rammeverk og Teisrud Development AS sin Networking-pakke. Appen eier presentasjonsvindu, skjermer, navigasjon og brukerdata; innloggingstjenesten eier Apple/Vipps og SMS/e-post-engangskoder.

Start med <doc:GettingStarted>, deretter <doc:Configuration> og <doc:NetworkingIntegration>. API-siden for hvert symbol beskriver parametere og feil. <doc:APIReference> gir en samlet oversikt.

## Bruksområder

| Behov | Hva Auth leverer | Hva app/tjeneste leverer |
| --- | --- | --- |
| REST/JSON | Access-token og én koordinert refresh | Networking-request og backendautorisasjon |
| Fil/bildeopplasting | Credential til riktig API-klient | Transfer-kontrakt, replay og fremdrift |
| Chat/realtime | Token ved tilkobling | Handshake, reconnect og kontobundet kanal |
| Offline-synkronisering | Lokal identitet og senere tokeninnhenting | Brukeravhengig kø, konfliktløsing og lagring |
| Apple/Vipps | Hosted OIDC-flyt og registrert connection-valg | Brokerintegrasjon, avtaler og tjenesteoppsett |
| SMS/e-post OTP | Browserrouting til tjenestens innlogging | Generering, levering og kontroll av koden |

Lokalt `signedIn` er ikke serverautorisasjon eller garanti om nettverkstilgang. Ingen live leverandørintegrasjon er verifisert av pakkens fixturetester. Detaljer og releasekrav finnes i <doc:TestingAndRelease>.

## Topics

### Kom i gang

- <doc:GettingStarted>
- <doc:Configuration>
- <doc:SessionLifecycle>
- <doc:NetworkingIntegration>

### Utvidelse og drift

- <doc:ProvidersAndExtensions>
- <doc:ErrorsAndRecovery>
- <doc:Security>
- <doc:TestingAndRelease>
- <doc:Architecture>
- <doc:APIReference>

### Sesjon og appintegrasjon

- ``AuthClient``
- ``AuthConfiguration``
- ``AuthIdentity``
- ``AuthState``
- ``AuthSessionObserver``
- ``AuthCredentialProvider``

### Browser og tjenesteadapter

- ``AuthLoginChoice``
- ``AuthAPIResource``
- ``AuthBrowserSession``
- ``SystemAuthBrowser``
- ``AuthOIDCAdapter``
- ``NativeOIDCAdapter``
- ``AuthTokenResponse``
- ``AuthIDTokenBinding``

### Feilhåndtering

- ``AuthError``
- ``AuthRecoveryAction``
