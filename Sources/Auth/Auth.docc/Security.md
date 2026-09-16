# Sikkerhet, protokoll og lagring

Kontroller som implementeres i pakken, og grenser som app og server må håndtere.

## Tjeneste- og klientmodell

Appen er en offentlig OIDC-klient. Native adapter bruker Authorization Code + PKCE S256 i systembrowser og har ingen client-secret-støtte. Apple leverer SHA-256, kryptografisk tilfeldighet og RSA-verifisering; Auth vedlikeholder protokoll- og parserkontrollene. Dokumentasjonen er ikke en sikkerhetssertifisering.

Standardgrunnlaget er [OIDC Core](https://openid.net/specs/openid-connect-core-1_0.html), [Discovery](https://openid.net/specs/openid-connect-discovery-1_0.html), [PKCE](https://www.rfc-editor.org/rfc/rfc7636) og [native app-flyt](https://www.rfc-editor.org/rfc/rfc8252). Tabellen nedenfor beskriver den konkrete implementasjonen, som bevisst støtter et avgrenset sett funksjoner.

## Authorize og callback

Verifier, state og nonce opprettes separat fra 32 tilfeldige bytes med SecRandomCopyBytes og canonical base64url uten padding. Challenge er SHA-256(verifier). Appen sender response_type=code, client_id, redirect_uri, scope, state, nonce, S256-felter og avtalt resource/connection.

Callback har maks 16 KiB og må matche scheme/host/port/percent-encoded path. Fragment og credentials avvises. Alle dupliserte querynavn avvises; hvert felt må ha verdi. state må matche. Hvis iss finnes, må issuer matche. code og error kan ikke forekomme sammen. En ikke-tom error blir providerRejected; authorization code må være ikke-tom før exchange.

En callback er ikke en innlogget identitet. Identitet utleveres først etter komplett tokenvalidering og generasjonskontroll.

## ID-token og JWK

| Kontroll | Implementasjon |
| --- | --- |
| Format | Tre JWS-segmenter; canonical, unpadded base64url; ID-token høyst 64 KiB. |
| Algoritme | Kun RS256. alg=none og andre algoritmer avvises. |
| Header | Ikke-tom kid på høyst 256 bytes. crit, b64, jku og x5u avvises. |
| Keyvalg | Akkurat én matching kid i issuerens JWKS. Tokenet velger ikke en ekstern key-URL. |
| Keytype | RSA; alg mangler eller er RS256; use mangler eller er sig; eventuelle key_ops må inneholde verify. |
| Privat keymateriale | Den valgte JWK-en kan ikke inneholde d, p, q, dp, dq eller qi. |
| RSA-verdier | Canonical n/e, ingen leading-zero UInt. Modulus 2048–8192 bit med høy bit satt og odd verdi; exponent opptil fire bytes, odd og minst 3. |
| Signatur | Apple SecKeyVerifySignature, PKCS#1 v1.5 SHA-256 over originale encoded segmenter. |
| Identitet | Eksakt issuer, ikke-tom ASCII subject høyst 255 bytes. |
| Audience | Client ID inngår; alle audiences tilhører eksplisitt tillitsliste; ingen duplikater. |
| azp | Må være client ID når flere audiences finnes eller azp er til stede. |
| Tid | Finite, ikke-negative NumericDates, ikke booleans. exp > nå; iat <= nå og iat < exp; eventuell nbf <= nå. |
| Nonce | Påkrevd match ved login. Ved refresh kontrolleres eventuell nonce mot kjent original nonce. |
| at_hash | Hvis til stede, SHA-256-basert hash av access-token må matche. |
| Refresh-binding | Samme issuer/subject og originalt audience-sett; eventuell returnert auth_time må matche original binding. |

Ingen klokkeleeway er aktiv. Original auth_time kan mangle i refresh-ID-token; hvis den returneres må den matche. Et ID-token kan legitimt mangle helt ved refresh, men kan ikke mangle ved førstegangs native login. En eldre lagret record uten audience-binding kan ikke godkjenne et nytt refresh-ID-token uten ny login.

## Responsgrenser og parsing

Discovery og tokenresponses begrenses til 64 KiB; JWKS til 256 KiB. Total tokenresponsegrense gjelder selv om en enkelt JWT har en høyere isolert maksimumsgrense. Access-token og eventuell refresh-token er ikke-tomme og høyst 16 KiB; token_type må være bearer. expires_in er finite, positiv, ikke boolean og høyst 31 536 000 sekunder. Utløpet beregnes fra tidspunktet før tokenrequesten, slik at svartiden ikke forlenger tokenets levetid.

Foundation parser JSON. StrictJSON avviser dessuten dupliserte feltnavn inklusive escaped stavemåter og scanner nesting på under 32 nivåer. JSON må være et objekt, ikke en root-array. Sensitive responser blir ikke en del av offentlig feilmelding.

## HTTP og key-cache

Endpoint HTTPS/origin-policy kontrolleres før sending. Alle redirects avvises. Requests bruker reloadIgnoringLocalCacheData, Accept application/json, POST form-encoding ved tokenutveksling og transportoptions som forbyr caching. URLRequest har 30 sekunders request-timeout; koordinert refresh har i tillegg samlet refreshTimeout.

Discovery/JWKS har fem minutters lokal TTL. JWKS_URI-endring tømmer cached keys. Ukjent kid henter JWKS på nytt én gang per valideringskall. Ingen tokenrequest gjentas for å hente keys. Samme-kid keyendring utløser ikke automatisk ekstra fetch etter signaturfeil; ny-kid rotasjon og TTL er den støttede cachekontrakten.

## Hva lagres

| Data | Sted/livsløp |
| --- | --- |
| Access-token | Kun klientminne til logout/restore/erstatning; ikke på disk. |
| ID-token | Kun verifisert providerlogout-hint i adapterminne; ikke på disk. |
| Refresh-token | Ett Keychain-element med minimal identitet/binding/karanteneflagg. |
| Issuer/subject, original nonce, audiences/auth_time | Samme Keychain-record som refresh-token. |
| SHA-256-tokenfingeravtrykk | Bounded minnehistorikk på høyst 256 for direkte rejected-token-håndtering. |
| Logout-markør | Én credential-fri byte [1] i Application Support/TeisrudAuth med hashed servicefilnavn. |
| Lease | Fil-lock og prosessregistrering; ingen credential/identitet i lockfil. |

Keychain bruker generic password, account=session, hashed service, ingen synchronizable/iCloud, eksplisitt Data Protection Keychain og WhenUnlockedThisDeviceOnly. Ingen shared access groups støttes. Elementet kan overleve avinstallering; local logout må slette eksplisitt. Legacy macOS-Keychain migreres ikke automatisk.

Credential-free markør skrives atomisk. Directory opprettes med 0700 og lockfile med 0600. På iOS har marker-directory/writes ingen file protection for å kunne uttrykke logout mens enheten er låst; de inneholder aldri tokens/identitet. Korrupte/uleselige markører feiler lukket. Fil-låsen holdes hele klientens levetid og unngår to koordinatorer for samme roterende credential i støttet container.

## Server og appens grenser

Backend må kontrollere API-tokenets issuer, audience, utløp og rettigheter via riktig JWT-/introspection-kontrakt. ID-token er ikke API-bearer. Appens signedIn-status kan ikke brukes som serverautorisasjon. Konto-linking, roller, revokering og kontosletting implementeres hos tjeneste/server.

Auth tømmer ikke appcacher, jobbkøer eller OS-bakgrunnsoverføringer. Logout tilbakekaller ikke serverutstedte tokens. Appen må forkaste gamle responses og beskytte brukerdata ved kontobytte. Ikke logg callbacks, authorization-URL-er, request bodies, tokens eller persondata i analytics/crash metadata.

Før produksjon kreves faktisk provider-/API-testing og en separat gjennomgang av egen protokollkode. Se <doc:TestingAndRelease>.
