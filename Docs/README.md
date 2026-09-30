# Dokumentasjon for Auth

Den komplette, kanoniske veiledningen ligger i [Auth.docc](../Sources/Auth/Auth.docc/Auth.md), og public API er kommentert direkte i Swift-koden for Xcode Quick Help/DocC.

| Veiledning | Innhold |
| --- | --- |
| [Kom i gang](../Sources/Auth/Auth.docc/GettingStarted.md) | Installasjon, appvindu, oppstart, login og første API-kall |
| [Konfigurasjon](../Sources/Auth/Auth.docc/Configuration.md) | Alle parametere/defaults, scopes, resource, callbacks, origins og namespaces |
| [Sesjonslivssyklus](../Sources/Auth/Auth.docc/SessionLifecycle.md) | Alle tilstander, restore, refresh, cancellation, rotasjon, kontobytte og logout |
| [Networking og bruksområder](../Sources/Auth/Auth.docc/NetworkingIntegration.md) | REST/JSON, transfers, realtime, offline/bakgrunn og tredjeparts-API |
| [Providers og utvidelse](../Sources/Auth/Auth.docc/ProvidersAndExtensions.md) | Apple/Vipps/OTP, hosted connections, adapter/browser/transport-kontrakter |
| [Feil og recovery](../Sources/Auth/Auth.docc/ErrorsAndRecovery.md) | Alle AuthError-cases, handlinger og Networking-feilmapping |
| [Sikkerhet](../Sources/Auth/Auth.docc/Security.md) | PKCE/JWS/JWK/claims, grensene, cache, Keychain og logout-markører |
| [Arkitektur](../Sources/Auth/Auth.docc/Architecture.md) | Alle produksjonsfiler, actors, generation, persistence og vedlikehold |
| [Samlet API-referanse](../Sources/Auth/Auth.docc/APIReference.md) | Alle public typer, properties, initializere, metoder og standardverdier |
| [Testing og utgivelse](../Sources/Auth/Auth.docc/TestingAndRelease.md) | Testsuiter, reell Keychain, DocC-bygg, CI og live releasekrav |

[ProviderSetup](ProviderSetup.md) beskriver konkret tjenesteoppsett. [Release](Release.md) beskriver signering og backend-/releasekontrakt. [Eksempelappen](../Examples/AuthExample/README.md) viser faktisk iOS/macOS-integrasjon.

Les .docc Markdown direkte på GitHub, eller bygg katalogen i Xcode for navigerbar dokumentasjon og symbolreferanser. Guides sine `<doc:...>`-lenker blir navigerbare i bygget DocC. Ingen genererte arkiver eller analyserapporter skal committes.

[GitHub-oppsett](GitHubSetup.md) beskriver offentlig distribusjon, CI og repository-innstillinger.
