# Konfigurasjon

Alle innstillinger og valideringsregler for én app, ett miljø og én API-resource.

## AuthConfiguration

Konfigurasjonen er en immutable Sendable/Equatable-verdi. Initializeren kaster `invalidConfiguration` ved ugyldige verdier. Validering skjer før browser eller credentialutveksling; korrekt syntaks erstatter ikke registrering hos tjenesten.

| Parameter | Standard | Betydning og kontroll |
| --- | --- | --- |
| issuer | Påkrevd | HTTPS-URL med host, uten user/password/query/fragment. Strengen må matche discovery og ID-token eksakt, inklusive trailing slash. |
| clientID | Påkrevd | Ikke-tom ID for offentlig native klient. Ingen secret støttes. |
| redirectURI | Påkrevd | Registrert login-callback. Ingen credentials, port, query eller fragment. |
| scopes | openid, offline_access | Må inkludere openid, være unike og ikke-tomme. Tillatte tegn er ASCII 0x21–0x7E unntatt anførselstegn og backslash. |
| apiResource | Påkrevd | Én av resource-kontraktene nedenfor. Inngår i lagringsidentiteten. |
| postLogoutRedirectURI | nil | Valgfri callback med samme syntaksregler som login. Kreves av medfølgende providerlogout. |
| keychainNamespace | Påkrevd | Ikke-tom verdi som skal identifisere app og miljø. Ikke bruk persondata eller tokens. |
| loginChoices | serviceSelection | Ikke-tom liste. Connection-navn må være ikke-tomme. Native adapter tillater bare et konfigurert valg. |
| ephemeralBrowserSession | false | Sendes til ASWebAuthenticationSession som preferanse om privat browserøkt. Er ikke en garanti om upstream logout. |
| trustedEndpointOrigins | tom liste | Ekstra HTTPS-origins for discovery-endepunkter. Ingen credentials/query/fragment; path er tom eller /. |
| trustedIDTokenAudiences | tom liste | Ikke-tomme, unike ekstra ID-token-audiences som faktisk er betrodde. Client ID er allerede tillatt. |
| refreshTimeout | 60 sekunder | Finite, positiv, høyst 3600. Samlet frist for én koordinert refresh inklusive forberedelse og validering. |

Scopelisten er ikke en liste over approller. Rettigheter og API-audience kontrolleres på serveren.

## API-resource

`AuthAPIResource.auth0Audience(String)` sender `audience` ved authorize og refresh. Verdien må være ikke-tom; den behandles som en leverandøridentifikator, ikke som et nettverksendepunkt. Ingen Auth0-SDK brukes.

`AuthAPIResource.oauthResource(URL)` sender `resource`. URL-en må ha scheme og må ikke ha fragment, user eller password. Konfigurasjonen krever ikke HTTPS for denne identifikatoren: den er ikke URL-en som credential-requesten sendes til. Tjenesten må støtte den avtalte resource-kontrakten.

API-resource og ID-token-audience er forskjellige: ID-token skal være til native klientens client ID. `trustedIDTokenAudiences` gjør ikke en annen API-resource automatisk tilgjengelig.

## Callback-typer

| Type | OS | Krav i app/tjeneste |
| --- | --- | --- |
| Eget scheme | iOS 17+, macOS 14+ | URL Types i appen, eksakt registrert URI hos tjenesten, host eller path i URI. |
| HTTPS | iOS 17.4+, macOS 14.4+ | Host og ikke-tom path, Associated Domains, AASA og registrert URI. Konfigurasjonen avvises på eldre OS. |

Custom scheme kan ikke være http, file, data eller javascript. Pakken tillater syntaktisk andre schemes, men appen bør bruke et eget, registrert scheme. Callback-validering sammenligner scheme, host, port og percent-encoded path; ikke legg ekstra queryparametere i redirectURI. Tjenestens response-parametere legges til callbacken under flyten.

## Discovery-endepunkter og tillit

Authorization, token, JWKS og eventuell end-session URL må bruke HTTPS. Origin betyr host og effektiv port; manglende port behandles som 443. Issuers origin er automatisk tillatt. Registrer bare kjente ekstra origins i `trustedEndpointOrigins` hvis tjenesten bruker flere domener.

Statiske queryparametere bevares. Navn som kolliderer med OAuth/OIDC-felter avvises, eksempelvis client_id, client_secret, redirect_uri, response_type, scope, state, nonce, code_challenge, code_challenge_method, grant_type, code, code_verifier, refresh_token, audience, resource, post_logout_redirect_uri, connection og id_token_hint. Redirects fra endpoint-requestene avvises. Også en annonsert valgfri end-session URL valideres under discovery.

## Isoler apper og miljøer

Lagring identifiseres av JSON-kodet liste med namespace, issuer-streng, client ID og resource-type/verdi, deretter SHA-256. Resource-typene er tagget for å unngå kollisjon mellom audience og resource. Scopes, callback, browserpreferanse og tillitslister inngår ikke i hashen.

Bruk for eksempel `com.company.app.staging` og `com.company.app.production`, med separate tjenesteregistreringer. Endring av namespace/issuer/client/resource gir en annen lagringsidentitet; gamle credentials migreres eller slettes ikke automatisk. Opprett ikke to klienter for samme identitet: `sessionAlreadyInUse` beskytter roterende credentials.

## Innloggingsvalg

`.serviceSelection` lar hosted UI velge metode. `.connection("registered-name")` sender connection-feltet. Connection er leverandørspesifikt, og den native adapteren sender det ikke ved refresh. Listen aktiverer ingen Apple/Vipps/OTP-integrasjon i seg selv. Se <doc:ProvidersAndExtensions>.
