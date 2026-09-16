# Release og appintegrasjon

Dette er en produktveiledning. Lokale fixturetester dokumenterer ikke live Apple-, Vipps- eller OTP-integrasjon.

## Før første utgivelse

1. Velg en offentlig OIDC-klienttjeneste og registrer staging/produksjon separat. Etabler nødvendige Apple/Vipps-avtaler og OTP-oppsett hos tjenesten. Ingen klienthemmeligheter skal ligge i appen.
2. Kjør eksempelappen på simulator, macOS og fysisk iPhone med registrerte callbacks. Kontroller login, avbrudd, restart, tokenrotasjon, nettverksbrudd, Keychain ved låst enhet og lokal/providerlogout.
3. Bekreft Go-API-kontrakten nedenfor. Test feil issuer/audience, utløp og at ID-token avvises som API-credential.
4. Publiser Auth til ønsket privat GitHub-repository, gi apputviklere lesetilgang og opprett NETWORKING_READ_TOKEN med minimal lesetilgang til SwiftNetworking. Ikke legg tokens i kildekode, package-URL-er eller Git-remotes.
5. Kjør GitHub-workflowen og krev grønn status før release. Den vanlige workflowen kjører macOS-tester, iOS-simulatortester, reell Keychain-test i signert iOS-appvert, formateringskontroll og eksempelappbygg på begge plattformer. Data Protection Keychain-test på macOS krever et faktisk Apple-utviklingssertifikat; kjør eksempelappens Test lokalt med valgt team, eller den eksplisitte macos-keychain-workflowen på en ferdig konfigurert signeringsrunner merket auth-keychain. Denne verifikasjonen er et separat releasekrav og blir ikke feilaktig godkjent av unsigned pakketester. Oppdater simulatornavn hvis runner-imaget endres.
6. Opprett første SemVer-tag først etter integrasjonsverifikasjon. Før 1.0 kan breaking changes øke minor; etter 1.0 må breaking changes øke major. Nye adapterkrav og async-throwing initializere i denne utviklingsversjonen er breaking changes.
7. Når Networking har en godkjent SemVer-release, vurder et eksplisitt kompatibelt versjonsintervall. Inntil da beholdes den publiserte, låste revisjonen.
8. La en separat sikkerhetsgjennomgang kontrollere egen OIDC/JWS-parser før produksjon. Kryptografi leveres av Apple, men protokollkontrollene vedlikeholdes av oss.

## Backendkontrakt

Backend må validere access token for riktig issuer, API-audience, utløp og tillatt signaturalgoritme eller bruke tjenestens sikre introspection-kontrakt for opaque tokens. Backend må ikke bruke appens signedIn-status som autorisasjon. Identitetsnøkkel er issuer + subject; e-post er ikke en sikker automatisk koblingsnøkkel.

Avklar konto-linking, roller/tilganger, token-/sesjonsrevokering og eventuell kontosletting på serveren. Rate limiting, OTP-utløp, engangsbruk og beskyttelse mot identitetsopplisting eies av tjenesten. Pakken kan ikke implementere eller bekrefte disse serverkontrollene uten servertilgang.

Lokal logout stanser appens bruk av credentials, men tilbakekaller ikke automatisk allerede utstedte tokens på serveren. Hvis produktet krever serverrevokering, må den separate serverkontrakten implementeres og testes. Ikke gjør lokal sletting avhengig av en vellykket nettverksrequest.

## Appenes ansvar

Del én AuthClient mellom scener. Observer AuthState for navigasjon og håndtering av feil, og tøm brukeravhengige cacher ved kontobytte/logout. Kanseller gamle requests og forkast sene responses. Opprett nye AuthCredentialProvider/HTTPClient etter vellykket login/restore; en tidligere bundet provider kan ikke bytte sesjon. Test forsinket 401 fra bruker A etter innlogging som bruker B, og gjeninnlogging som samme bruker med samme tokenverdi. Ingen av disse forespørslene skal replayes. Marker beskyttede Networking-requests eksplisitt med requiresAuthentication. Ikke logg callbacks, authorization-URL-er, request bodies eller credentials.

Keychain bruker WhenUnlockedThisDeviceOnly. Bakgrunnsarbeid med låst enhet må tåle utilgjengelig lagring; pakken utvider ikke automatisk tilgangsnivået. App Extensions, credential-deling mellom apper og flere samtidige API-resources trenger egne kontrakter og støttes ikke av denne første versjonen.

## Verifikasjon uten secrets

Registrer godkjent Auth-/Networking-revisjon, OS-versjoner og hvilke faktiske innloggingsmetoder som er testet i utgivelsens integrasjonsdokumentasjon. Oppbevar aldri tokens, engangskoder eller persondata i testresultater. Merk manglende live verifikasjon eksplisitt; en grønn fixturetest er ikke bevis på leverandørintegrasjon.
