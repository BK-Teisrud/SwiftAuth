# AuthExample

Åpne AuthExample.xcodeproj i Xcode og velg AuthExample-schemet. Prosjektet er en faktisk SwiftUI-app for iOS 17+/macOS 14+ og bruker lokal Auth samt samme eksakte offentlige Networking-release. Ingen tredjeparts-SDK-er brukes.

Sett targetets brukerkonfigurasjon i Build Settings:

| Innstilling | Verdi |
| --- | --- |
| AUTH_ISSUER | Eksakt HTTPS-issuer fra discovery |
| AUTH_CLIENT_ID | Registrert public/native client ID |
| AUTH_RESOURCE | API-resource for RFC 8707; bytt kode til auth0Audience hvis tjenesten bruker audience |
| AUTH_API_URL | HTTPS-base-URL for eget staging-API |

Ingen client secret eller tokens skal legges inn. Registrer com.teisrud.authexample://auth/callback og com.teisrud.authexample://auth/logout hos tjenesten. Appens Info.plist inneholder callback-schemet. Endrer du redirect URI, må både appregistrering, kildekode og tjenesteoppsett oppdateres.

Velg utviklingsteam for fysisk enhet. Ingen signeringsteam er hardkodet. Uten gyldig konfigurasjon viser appen en trygg konfigurasjonsfeil; den kontakter ikke en oppdiktet tjeneste.

Appen viser restore, eksplisitt systembrowser-login, avbrudd, beskyttet Networking-request, lokal logout og providerlogout fulgt av lokal logout. API-knappen kaller protected relativt til AUTH_API_URL; tilpass dette til backendens faktiske kontrakt. hosted UI må være konfigurert til metodene som skal tilbys, eksempelvis Apple/Vipps og e-post/SMS. UI-et logger ikke tokens eller API-responsinnhold.

Bygg uten signering for lokal kompilasjonskontroll:

```text
xcodebuild -project AuthExample.xcodeproj -scheme AuthExample -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project AuthExample.xcodeproj -scheme AuthExample -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Full live verifikasjon krever tjenesteoppsett og er beskrevet i ../../Docs/ProviderSetup.md og ../../Docs/Release.md.

## Ekte Keychain-integrasjonstest

AuthExample-schemet inkluderer AuthExampleTests. Kjør Test i Xcode eller xcodebuild test med iOS-simulator. Appverten signeres med eksplicitte Keychain-entitlements; samme reelle lagringstest kjøres også i macOS-appverten. Swift Packages generiske testvert mangler nødvendige rettigheter til Data Protection Keychain, så akkurat round-trip-testen kjøres i appverten på begge plattformer. Fixture- og sesjonstester kjøres fortsatt i pakkens testtarget. Entitlements bruker AppIdentifierPrefix fra valgt utviklingsteam ved fysisk enhet; ingen team-ID er hardkodet.

På macOS må du velge et Apple-utviklingsteam med gyldig utviklingssertifikat for Test. Ad hoc-signering støtter ikke eksempelappens nødvendige Keychain-entitlements. Et usignert build beviser kompilering, ikke Data Protection Keychain-tilgang. Den separate macos-keychain-workflowen er manuell og forventer en konfigurert signeringsrunner; den oppretter ingen sertifikater eller avtaler.

Eksempelappen oppretter en ny sesjonsbundet AuthCredentialProvider og HTTPClient etter vellykket login/restore, og fjerner API-klienten ved lokal logout. Gamle API-klienter kan ikke hente credentials fra en ny sesjon. Appene må også kansellere gamle forespørsler og forkaste sene responses ved kontobytte.
