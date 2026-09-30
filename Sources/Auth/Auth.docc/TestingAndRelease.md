# Testing, dokumentasjonsbygg og utgivelse

Hvordan kontrollene kjøres, hva de beviser og hvilke integrasjoner som må verifiseres separat.

## Lokale pakketester

Kjør fra Auth-mappen:

```text
swift test
xcrun swift-format lint --strict --recursive Package.swift Sources Tests Examples
git diff --check
```

Swift Testing er Apples testingbibliotek. Testene bruker syntetiske tokens og lokale fixtures, ikke providerkontoer. Package.swift og eksempelappen har kun den offentlige Networking-avhengigheten, låst til eksakt release.

| Testsuite/fil | Dekning |
| --- | --- |
| SessionTests | Login/restore, redigert status/DTO, shared refresh/rotasjon, manglende erstatning, karantene over restart, lagringsfeil, logout under login/refresh og namespace-isolering. |
| ProductionSessionTests | Før-send forutsetninger/save-feil, short-lived uten refresh, browserstopp, varig logout ved klientbytte og lease/flock/deinit. |
| SessionRegressionTests | Kontobytte med forsinket 401, samme token på ny login, delayed same-session rejection, short-lived med refresh, reauth-status, cancelled waiter og timeout før/etter send med sene resultater. |
| NetworkingIntegrationTests | Protected request→401→recovery, access-token og utløps-/konfigurasjonskontroller. |
| OIDCValidationTests | Virkelige Apple RSA-signaturer, claims/header/callbackfeil, ny-kid keyrotasjon, original binding/restart, native refreshresponsvarianter, ugyldige JWKs, endpoint-tillit og rå URLSession-feilmapping. |
| JSONSafetyTests | Duplikatnavn inklusive escaped skrivemåte og uavhengige objekter. |
| KeychainIntegrationTests | Faktisk save/load/update/delete/isolation/accessible-attributt i appvert; varig credential-fri marker og fail-closed corrupt marker. |

Testantall endrer seg med utviklingen. Parameteriserte cases er flere inputvarianter under én testdefinisjon. Ikke bruk et rent antall som bevis på live sikkerhet eller providerkompatibilitet.

## iOS-pakketester

```text
xcodebuild -scheme Auth -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/auth-ios-tests test
```

Velg en faktisk tilgjengelig simulator i din Xcode. Minimum deployment er iOS 17, men en kjøring på nyere simulator beviser ikke at alle eldre OS-versjoner er live testet. Custom/HTTPS API-grenser må kontrolleres med faktisk callbackoppsett.

## Reell Keychain i appvert

Swift Packages generiske testvert mangler nødvendige rettigheter til Data Protection Keychain. Round-trip-testen er derfor disabled der og kjøres med AUTH_HOSTED_KEYCHAIN_TESTS i AuthExampleTests. De credential-frie markørtestene kan også kjøre i packageverten.

```text
xcodebuild -project Examples/AuthExample/AuthExample.xcodeproj -scheme AuthExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/auth-hosted-ios-tests test
```

Appvertens Test-scheme har tre Keychain/marker-tester. Signeringsentitlements og accessible-attributt kontrolleres gjennom den reelle Apple-lagringen. Fysisk enhet og låst enhet er fortsatt egne integrasjonsscenarier.

På macOS velges et faktisk Apple-utviklingsteam med gyldig utviklingssertifikat. Ad hoc/unsigned build erstatter ikke en Data Protection Keychain-test. Eksempelappen har entitlements, men ingen team-ID/certifikater hardkodes.

## Bygg dokumentasjonen

Åpne pakken i Xcode og bruk Build Documentation for Auth-schemet. DocC-katalogen ligger i Sources/Auth/Auth.docc, og public API-kommentarene brukes også i Quick Help.

CLI uten et tredjeparts DocC-plugin:

```text
swift package dump-symbol-graph --skip-synthesized-members
xcrun docc convert Sources/Auth/Auth.docc --additional-symbol-graph-dir .build/x86_64-apple-macosx/symbolgraph --output-path /tmp/Auth.doccarchive --warnings-as-errors
```

Eksemplet viser Intel Mac. På Apple Silicon og andre verktøyversjoner bruker du katalogen som dump-symbol-graph oppgir, eksempelvis .build/arm64-apple-macosx/symbolgraph. Ikke commit .doccarchive, symbol graphs, DerivedData eller testresultater. DocC-arkivet kan åpnes i Xcode; websitehosting/publisering er en egen handling.

Swift-kodeblokkene er enten hele declarations/imports eller snippets med eksplisitt eksisterende auth/api/window/transport. Ikke kopier plassholderissuer/client ID som produksjonskonfigurasjon. Den kjørbare eksempelappen er referansen for appvindu og faktisk entry point.

## CI

ci.yml kjører macOS-pakketester på minimum og gjeldende toolchain, format, DocC-bygg med warnings-as-errors, iOS-pakketester, iOS-appvertens Keychain og eksempelappbygg på begge plattformer. Networking hentes fra sin offentlige eksakte SemVer-release uten credentials. Xcode-path og simulatornavn må finnes på runneren. Workflowfilen alene er ikke grønn CI.

macos-keychain.yml er manuell, på forhånd konfigurert self-hosted macOS-runner med label auth-keychain, faktisk development_team og sertifikat/profile. Den kjøres ikke automatisk på vilkårlige pull requests. Den oppretter ingen sertifikater eller secrets.

## Før produksjon

1. Registrer staging/production issuer, public klienter, callbacks og API-resource.
2. Etabler nødvendige provideravtaler og Apple/Vipps/SMS/e-post-oppsett hos valgt tjeneste.
3. Test hosted login/avbrudd/HTTPS callback/restart på simulator, macOS og fysisk iPhone.
4. Test faktisk backendvalidering av riktig/feil access-token og avvisning av ID-token som bearer.
5. Test rotasjon, låst Keychain, network transitions, samlet timeout, tapt respons og interaktiv recovery.
6. Test logout og kontobytte med gamle 401/200-responses, realtimekanaler, cacher og fil-/syncjobs.
7. Kjør signert macOS-Keychain-test og få faktisk grønn CI.
8. Gjennomfør separat sikkerhetsreview av egen OIDC/JWS/parserkode.
9. Publiser godkjent Auth-revisjon og SemVer-tag med kompatibel Networking-versjon/revisjon.

Ingen live provider-/backendintegrasjon er dokumentert som verifisert ennå. Det finnes lokale fixturetester og iOS-appvertstester; de erstatter ikke stegene over. Ikke lagre tokens/OTP/persondata i integrasjonsresultater. Utgivelsesveiledningen i Docs/Release.md og tjenesteoppsettet i Docs/ProviderSetup.md utdyper ansvaret.

## Versjonsendringer

AuthCredentialProvider er actor og binder seg til første vellykkede credential-sesjon. Bytt provider/HTTPClient etter login/restore. Offentlige AuthClient-init er async throws og kan gi sessionAlreadyInUse. Før 1.0 kan breaking changes øke minor; etter 1.0 krever de major. En publisert 0.x-release dokumenterer pakke-API-et, ikke live produksjonsgodkjenning av en bestemt provider eller backend.
