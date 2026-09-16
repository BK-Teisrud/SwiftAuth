# Sesjon, refresh og logout

Livssyklus og samtidighetskontrakt for AuthClient.

## Opprettelse og eierskap

Offentlige initializere er async throws, men starter ikke discovery eller login. Standardvarianten oppretter NativeOIDCAdapter, tar en lease og velger Keychain-lagring. Adaptervarianten bruker adapterens immutable konfigurasjon. Initial status er `restoring`.

Del én klient mellom scener. Lease varer til klienten deinitialiseres/prosessen avsluttes, også etter logout. Ny API-klient krever ikke ny AuthClient. En annen levende koordinator med samme lagringsidentitet avvises; app extensions og delte access groups støttes ikke.

## Offentlige tilstander

| AuthState | Betydning | Apphandling |
| --- | --- | --- |
| restoring | Lokal lagring er ikke ferdig avklart, eller restore feilet. | Avvent/håndter restore-feilen; ikke anta manglende bruker. |
| signedOut(problem:) | Ingen aktiv lokal sesjon; kan inneholde slette- eller loginfeil. | Vis appens innloggingsvalg eller lagringsfeil. |
| signingIn | Interaktiv login pågår. | Vis fremdrift og tilby eksplisitt avbrudd. |
| signedIn(identity, problem:) | Lokal identitet/sesjon finnes; credentialtilgang kan likevel være blokkert. | Håndter problem før API-bruk. Ingen serverrettigheter garanteres. |
| reauthenticationRequired(identity?, reason:) | Ingen brukbar credentialvei uten ny login eller håndtering av årsaken. | Bruk reason/recoveryAction; identitet kan beholdes. |

`refreshOutcomeUnknown` presenteres bevisst som signedIn med problem, fordi lokal identitet beholdes selv om refresh blokkeres. Avvist refresh og andre blokkerende refresh-feil gir reauthenticationRequired. Alle statusverdier er uten tokens.

## Restore

1. Avvis restore når login, browserstopp eller delt refresh pågår.
2. Bytt operasjonsgenerasjon og lokal sesjons-ID, tøm access-token og tokenfingeravtrykk.
3. Hvis logout-markør finnes, fullfør Keychain-sletting og fjern markøren før load.
4. Les StoredSession og kontroller versjon 1, issuer, subject og refresh-token.
5. Gjenopprett identitet og eventuell refresh-karantene. Ingen nettverksrequest skjer her.

Mangler Keychain-elementet, blir status signedOut. Låst Keychain eller ugyldige data gir eksplisitt feil og restoring. Etter slettefeil i samme klient er ny logout-retry nødvendig før restore; en ny klient/prosess bruker den varige markøren til å fullføre sletting.

## Login og avbrudd

Login krever et konfigurert valg og tilgjengelig lagring uten pending logout. Pågående refresh invalideres. Hvis credential kan ha vært sendt, beholdes konservativ karantene. En annen interaktiv login avvises med loginAlreadyInProgress.

Et verifisert resultat installeres bare når operasjonsgenerasjon og login-ID fortsatt matcher. Ny refresh-token lagres før access-token/status publiseres. Hvis login ikke gir refresh-token, fjernes tidligere lagret sesjon og access-token brukes bare i minnet.

Vellykket login gir ny sesjons-ID, også for samme bruker. Feilet eller avbrutt login beholder tidligere lokal sesjon når den finnes; et eksisterende krav om reauthenticationRequired oppheves ikke. Feil betyr derfor ikke alltid signedOut.

`cancelLogin()` gjør ingenting hvis klienten ikke har en aktiv login. Ellers invalideres resultatet før adapter/browser stoppes. Task-cancellation av login utløser også stopp. Sene resultater kan gi operationInvalidated; explicit cancellation og callbackavbrudd er ikke nødvendigvis samme feilkode.

## Access-token og refresh-margin

Med refresh-token beregnes margin ved installasjon som min(60 sekunder, 10 % av tokenets gjenværende levetid). Et token med 30 sekunder igjen får 3 sekunders margin. Uten refresh-token brukes et token frem til faktisk utløp. Utløpte tokens utleveres aldri.

Hvis token etterspørres under login/browserstopp, kastes loginAlreadyInProgress. Uten brukbart token og uten refresh-token kastes reauthenticationRequired. API-bruk starter aldri nettleserinnlogging.

## Én delt refresh

```text
Forberedelse/discovery
  → kontroll av generasjon og cancellation
  → lagre refreshInFlight = true
  → én tokenrequest
  → verifiser respons/identitet og eventuell ID-token-binding
  → lagre rotert refresh-token eller behold legitimt manglende erstatning
  → installer access-token og fullfør resultat atomisk i actor-turn
```

Alle samtidige tokenkall deler samme task. Én konsument som kanselleres får CancellationError uten å stoppe refresh for andre. Logout/ny login invaliderer hele operasjonen. refreshTimeout dekker hele refresh fra forberedelse til ferdig resultat; brukerens tid i login-browseren har ingen tilsvarende samlet frist.

| Feilfase | Credential-policy |
| --- | --- |
| Før varig markering, for eksempel discovery eller Keychain-save | Ingen refresh sendes; nytt forsøk er tillatt. |
| Etter mulig sending, timeout/tapt respons | refreshOutcomeUnknown, blokkert retry, markør beholdes over restart. |
| invalid_grant | refreshRejected; permanent avvisning forsøkes lagret. |
| Verifisert respons, lagring feiler | Access-token publiseres ikke; gammel diskcredential forblir i karantene. |
| Suksess | Ny credential lagres før token utleveres; markering oppheves av ny record. |

Appavslutning etter markering kan gi ukjent utfall selv hvis HTTP-requesten ennå ikke nådde serveren. Dette er et bevisst konservativt valg. Ikke slett markeringen manuelt eller retry gammel roterende tokenfamilie blindt.

## Lokal logout

Logout endrer generasjon/sesjons-ID, kansellerer refresh og tømmer minne. En credential-fri, atomisk markør skrives før Keychain-sletting. Sletting forsøkes også når markørlagring feiler. Markøren fjernes etter vellykket sletting.

Status er signedOut også når sletting feiler, men metoden kaster feilen. Diskcredentials kan da fortsatt finnes. Hvis både markering og sletting feiler, brukes logoutPersistenceUnavailable; ingen varig garanti kan gis når begge mekanismer er utilgjengelige. Gjenta logout når lagring er tilgjengelig. Ikke koble nettverksrevokering til nødvendigheten av lokal opprydding.

## Providerlogout

`logoutAtProvider()` bruker separat systembrowser, end_session_endpoint, post-logout callback og tilfeldig state. Verifisert ID-token brukes som hint bare når det finnes i minnet. Etter restart/lokal logout kan hint mangle. Tjenesten må da støtte client_id uten hint.

Kjør providerlogout før lokal logout hvis hint kreves, og fullfør lokal logout også hvis providerlogout feiler. Providerlogout alene endrer ikke lokal AuthState eller credentials. Det garanterer ikke logout fra Apple/Vipps eller andre apper og er ikke tokenrevokering.

## Kontobytte og data

Opprett ny AuthCredentialProvider/HTTPClient etter vellykket login/restore. Kanseller egne gamle requests og forkast sene responses, også 200-responses. Stopp realtime og bytt brukeravhengige køer/cacher. Auth kan forhindre credential-replay på tvers av sesjoner, men kan ikke identifisere eller tømme appens brukerdata.
