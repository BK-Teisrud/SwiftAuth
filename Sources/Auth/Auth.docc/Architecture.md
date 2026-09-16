# Arkitektur og vedlikehold

Ansvarsdeling for alle produksjonsfiler og kontraktene mellom dem.

## Modulgrense

Ett Auth-target eksporterer sesjons-API, browser/adapters og Networking-provider. Interne helpers er ikke stabile app-API-er. Pakken har ingen SwiftUI-skjermer, appnavigasjon, database, profiler eller DesignSystem. Eksempelappens UI er kun en separat integrasjonsvert.

```text
App / AuthSessionObserver (MainActor)
  → AuthClient (actor, lagring og sesjonslivssyklus)
      → AuthOIDCAdapter / NativeOIDCAdapter (MainActor, browser)
          → OIDCService (egen actor, HTTP/cache/parsing/validering)
      → SessionStorage / KeychainSessionStorage (synkrone commits)
      → SessionLease / SessionFiles (lease og logout-markør)
Networking HTTPClient
  → AuthCredentialProvider (actor, sesjonsbinding)
      → AuthClient
```

## Filoversikt

| Fil | Ansvar |
| --- | --- |
| Configuration/AuthConfiguration.swift | Immutable konfigurasjon, URI/scopes/tillitsliste-validering og hashed storage identity; login/resource-enums. |
| Session/AuthClient.swift | Offentlig sesjonsactor, generasjon, observers, login/restore/logout, delt refresh, tidsfrist og atomisk persistence/resultat. |
| Session/SessionContext.swift | Lokal sesjons-ID, stored/access, refresh-block, installasjon av adaptiv margin og fallback AuthState. |
| Session/AuthState.swift | Tokensfri identitet og observerbare tilstander. |
| Session/AuthSessionObserver.swift | MainActor/Observation-adapter, weak observer-task og cancellation ved deinit. |
| Session/AsyncResultGate.swift | NSLock-beskyttet single-result continuation-gate; kansellerbar waiter uten å stoppe shared task. |
| Session/SessionLease.swift | Prosessregistrering og OS flock; holder fil-descriptor, frigjør ved deinit. |
| Credentials/AuthCredentialProvider.swift | Networking CredentialProvider med immutable binding til første vellykkede credential-sesjon. |
| Browser/AuthBrowserSession.swift | Injectable browserprotocol og ASWebAuthenticationSession med continuation/operation-ID/presentation anchor. |
| OIDC/AuthOIDCAdapter.swift | Betrodd tjenesteprotocol og redigert sensitiv DTO; original ID-token-binding. |
| OIDC/NativeOIDCAdapter.swift | Interaktiv operation-ID, PKCE/state/nonce, authorize/resource/connection, refresh-forberedelse og providerlogout-hint. |
| OIDC/OIDCService.swift | Discovery/endpoint-policy, TTL/key-cache, bounded HTTP, typed tokenrespons og valideringskoordinering utenfor MainActor. |
| OIDC/IDTokenValidator.swift | JWS/JWK/RS256/claimkontroller og ett verifisert identitet/binding-resultat; DER public-key-format for Apple. |
| OIDC/OIDCCallbackValidator.swift | Ren callbackadresse/state/issuer/duplikatkontroll. |
| OIDC/OIDCEncoding.swift | Apple SHA/random, canonical base64url og StrictJSON duplicate/depth-kontroll. |
| Storage/SessionStorage.swift | Versionert StoredSession, sync storageprotocol, Keychain, atomisk pending-logout-marker og sikre lagringsfeil. |
| Storage/SessionFiles.swift | Credential-fri Application Support-directory, tillatelser og iOS file-protection-policy. |
| Errors/AuthError.swift | Safe Error-enum og foreslåtte recoveryAction-verdier. |

## Actor- og generasjonsmodell

MainActor brukes til browserpresentasjon, adapterens interaktive bookkeeping og UI-observasjon. OIDCService har egen actor, så HTTP-forberedelse, JSON, cache og SecKey-validering ikke utføres som MainActor-arbeid. AuthClient serialiserer sesjonsendringer; ingen eksklusivitet antas over await.

Operasjonsgenerasjon skifter ved restore/login/avbrudd/logout og hindrer sene commits. Sesjons-ID skifter ved restore, vellykket login og logout og hindrer API-klientens credentialbinding fra å følge en annen login. Refresh beholder sesjons-ID. Delt refresh har også egen ID slik at cleanup/sent resultat fra gammel task ikke kan endre en nyere task.

Keychain/filsletting er synkront der commit følger generasjonskontroll. Det gjør sjekk→commit atomisk i actor-turn. Det betyr ikke at lagring aldri kan feile eller at bakgrunnsarbeid kan bruke WhenUnlocked-data ved låst enhet.

## Persistence-record

StoredSession versjon 1 inneholder identity, refreshToken, optional loginNonce/idTokenBinding, refreshRejected og refreshInFlight. JSONEncoder/Decoder er lagringsformatet. Nye optional binding-felter kan mangle i eldre records; policyen krever login hvis ny ID-token ikke kan bindes sikkert. Ukjent version eller ugyldige required metadata feiler med storage. Ingen generell migrasjonsmotor finnes.

Logout-marker og Keychain er to separate mekanismer. Marker før delete hindrer restart fra å restaurere credentials når delete feiler. Hvis begge writes/deletes er utilgjengelige, kan ingen varig garanti lages; feilen er eksplisitt.

## Vedlikehold

Endre kontrakter samlet i kildekommentarer, DocC-guider og eksempelapp. Ved endring av claimregler, key-cache, callback, actorgrenser eller commitrekkefølge må faktiske native signatur-/protokolltester oppdateres. Ikke legg til ekstra targets eller protokoller bare for filstørrelse; bevar det enkle app-API-et.

Auth.docc er den kanoniske komplette veiledningen. README og Docs/README peker dit; ProviderSetup og Release er konkrete oppsetts-/utgivelsesveiledninger. Ingen analyserapporter skal legges i repositoryet.
