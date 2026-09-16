# Oppsett av innloggingstjeneste og integrasjonstest

Dette er produktveiledning og en integrasjonssjekkliste. Ingen live tjeneste er satt opp eller verifisert av bibliotekets lokale fixturetester.

## Generell OIDC-adapter og valgfritt Auth0-oppsett

NativeOIDCAdapter bruker ingen tjeneste-SDK. Velg en OIDC-tjeneste som oppfyller de dokumenterte discovery-, endepunkt- og RS256-kravene. Innloggingsmetodene leveres hos tjenesten.

Hvis Auth0 velges: Opprett én Native/public application per app/miljø. Token endpoint authentication må være None. Aktiver Authorization Code med PKCE S256 og refresh-token grant. Registrer eksakte custom-scheme callback-URI-er og post-logout-URI-er. Opprett Go-API-ets resource/audience, velg RS256-signerte ID-tokens og aktiver offline access for API-et. Bruk sikker rotasjon, passende levetider og dokumenter reuse-policyen. Konfigurasjonen må peke til den eksakte issuer-strengen fra discovery, inkludert eventuell slash.

I appen registreres callback-schemet under URL Types (`CFBundleURLTypes` / `CFBundleURLSchemes`); eksempel: com.teisrud.appone. Dette er appens registrering, ikke en verdi biblioteket leser automatisk. Minimum iOS 17-implementasjonen støtter custom schemes; HTTPS/universal-link-callback støttes fra iOS 17.4/macOS 14.4 med Associated Domains og korrekt AASA-oppsett; konfigurasjonen avvises på eldre OS.

Aktiver bare innloggingsmetoder som er tillatt av produktet. Slå av username/password-database connections for disse appene. Innloggingstjenesten må eie OTP-generering, forsøk/utsending, engangsbruk, utløp, anti-enumeration og misbruksbeskyttelse.

[Auth0s passwordless Universal Login](https://auth0.com/docs/authenticate/passwordless/passwordless-with-universal-login) beskriver oppsett for e-post/SMS og connection-valgene email/sms. Når både SMS og e-post er aktivert, må valget testes eksplisitt; ikke anta at hosted UI automatisk presenterer alle alternativer. Apple må konfigureres som en faktisk social connection med nødvendige registreringer hos Apple og broker.

Vipps er foreløpig en planlagt metode. [Vipps Login](https://developer.vippsmobilepay.com/docs/APIs/login-api/login-api-quick-start/) krever leverandøroppsett og credentials. Eventuelle klienthemmeligheter for Vipps/Apple oppbevares hos brokeren/serveren, aldri i appen. Et connection-navn i AuthConfiguration er kun routing til en eksisterende, testet brokerconnection; det etablerer ingen avtale eller ferdig Vipps-støtte. Den valgte brokerens mulighet til å koble Vipps må avklares før dette aktiveres.

## Go-API

Valider riktig API-access-token: issuer, audience, utløp og rettigheter. Bruk tjenestens støttede validering for opaque tokens og JWKS/signaturvalidering for JWT-er. Ikke godta ID-token som API-bearer. Backend eier brukerpost, rettigheter og deduplisering/konto-linking. Issuer + subject er identitetsnøkkelen; ikke koble kontoer automatisk etter e-post.

## Releasekrav på simulator og fysisk enhet

1. Sett opp to appkonfigurasjoner med separate client IDs, callback-URI-er, API-resources og namespaces. Verifiser at staging/produksjon og appene aldri deler credentials.
2. Test Apple-login, en faktisk Vipps-brokerconnection og både e-post- og SMS-engangskode som skal tilbys. Test avbrudd og avvisning, og kontroller at appen ikke samler inn passord/koder.
3. Verifiser systembrowser-presentasjon, callback-registrering og gjenopptak på simulator og fysisk enhet. Ikke merk dette verifisert etter kun fixturetester.
4. Send et beskyttet kall til riktig Go-API med access token. Verifiser at annet API/audience og ID-token avvises på serveren.
5. Restart appen og verifiser Keychain-restore, én delt refresh, rotasjon og forsinket 401. Test låst Keychain, samlet refreshTimeout før/etter sending, timeout/tapt refresh-respons og ny login etter ukjent utfall. Test korte access-tokenlevetider uten gjentatt refresh ved hvert kall.
6. Logout mens login/refresh pågår. Verifiser at sent resultat ikke gjenoppretter sesjonen. Test eksplisitt slettefeil og retry av sletting.
7. Test separat providerlogout og dokumenter faktisk effekt på nettlesersesjon og andre apper. Ingen generell upstream-logout loves.
8. Registrer verifisert issuer/Auth-revisjon, OS-versjoner og testresultater i release-/integrasjonsdokumentasjonen først etter faktisk gjennomføring, uten secrets eller personopplysninger.

Ingen av stegene med live leverandører er gjennomført ennå; de krever tjenesteoppsett, avtaler og app-/enhetstilgang.

## Endepunkter og logout

Hvis discovery annonserer endepunkter på en annen origin enn issuer, registrer bare nødvendige HTTPS-origins i trustedEndpointOrigins. Dette er en eksplisitt tillitsliste, ikke tillatelse til redirects. Kontroller at ID-token-algoritmen er RS256 og at API-resource-parameteren stemmer med tjenestens kontrakt; Auth0 audience og RFC 8707 resource er ulike innstillinger.

Providerlogout bruker id_token_hint bare fra et allerede verifisert ID-token i minnet. Kjør logoutAtProvider før logout når hint kreves; etter restart er hint tilgjengelig først etter en vellykket ID-token-utstedelse. Tjenester uten støtte for logout uten hint må håndteres eksplisitt. Lokal logout skal gjennomføres også hvis providerlogout feiler.
