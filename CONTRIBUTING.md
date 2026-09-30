# Bidrag og vedlikehold

Auth er proprietær programvare fra Teisrud Development AS. Tilgang til repositoryet gir ingen bruks- eller distribusjonsrettigheter; se [LICENSE](LICENSE). Bidrag avtales med repositoryeieren.

## Utvikling

Bruk Swift 6 og en Xcode-versjon som dekkes av CI. Pakken støtter iOS 17 og macOS 14. Den offentlige [SwiftNetworking-avhengigheten](https://github.com/BK-Teisrud/SwiftNetworking) er låst til en eksakt release i Package.swift og krever ingen credentials.

Produksjonskode, tester og utviklingsverktøy skal være Swift. Apple-rammeverk og egen Networking-pakke er avhengighetene. Nødvendig YAML og prosjektkonfigurasjon er tillatt. Se [AGENTS.md](AGENTS.md) og [arkitekturen](Sources/Auth/Auth.docc/Architecture.md).

## Kontroller før pull request

Kjør fra repositoryroten:

```text
swift test
xcrun swift-format lint --strict --recursive Package.swift Sources Tests Examples
git diff --check
```

Ved endringer i OIDC, lagring eller sesjonslivssyklus kjøres relevante protokoll-/signaturtester og reelle Keychain-tester. Ved dokumentasjonsendringer bygges DocC med warnings-as-errors. Komplette kommandoer og plattformkrav finnes i [testing og utgivelse](Sources/Auth/Auth.docc/TestingAndRelease.md).

Oppdater API-kommentarer, DocC og eksempelapp når kontrakter endres. Oppgi problemet, resultatet og faktisk utført verifikasjon i pull request. Ikke påstå live providerstøtte basert på fixturetester. Analyserapporter og funnlister skal aldri legges i repositoryet; produkt- og integrasjonsdokumentasjon vedlikeholdes.

Ikke commit byggprodukter, maskinspesifikke innstillinger, tokens, OTP, persondata eller signeringsnøkler. Del sikkerhetsproblemer gjennom [sikkerhetsrutinen](SECURITY.md).
