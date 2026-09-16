# Oppsett på GitHub

Hvordan laste opp Auth og konfigurere repositoryet uten å ta med lokale bygge- eller credentialfiler.

## Hva skal lastes opp?

Commit Package.swift, Sources, Tests, Docs, README, Examples, LICENSE, AGENTS.md, CONTRIBUTING.md, SECURITY.md og GitHub-/Git-konfigurasjonen. Behold eksempelappens shared scheme, entitlements og Package.resolved; de er del av reproducerbar appintegrasjon. Rotens library-lockfile ignoreres fordi Networking allerede er låst til en eksplisitt revisjon i manifestet.

.gitignore utelater SwiftPM-cache/mirrors, Xcode-brukerdata, bygg/test-/coveragefiler, generert DocC, lokale miljøfiler og private signeringsfiler. .gitattributes normaliserer tekst til LF og markerer binære filer. .editorconfig gir editorene samme grunninnstillinger.

Ignore-regler gjelder ikke filer som allerede er sporet. Kontroller alltid Git-status og innholdet som skal committes. Analyserapporter skal aldri opprettes eller lastes opp.

## Første opplasting

Repositoryet er allerede initialisert med Git. Opprett et tomt repository i ønsket GitHub-konto/organisasjon, uten automatisk README, lisens eller gitignore. Velg privat repository for intern proprietær kode. LICENSE beholder alle rettigheter hos Teisrud Development AS.

Bruk Xcode/valgt Git-klient, eller kjør følgende fra Auth-mappen. Erstatt OWNER/REPOSITORY med det faktisk opprettede repositoryet:

```text
git status --short
git add .
git diff --cached --check
git diff --cached --stat
git diff --cached
git commit -m "Prepare Auth package for GitHub"
git remote add origin https://github.com/OWNER/REPOSITORY.git
git push -u origin HEAD
```

Ingen remote-URL er hardkodet for Auth. Kommandoene oppretter ikke release eller tag. Hvis origin allerede finnes, kontroller git remote -v og oppdater riktig remote gjennom Git-klienten. Bruk credential manager eller GitHubs normale autentisering; ingen credential skal stå i remote-URL-en. Push av HEAD bevarer gjeldende branchnavn.

## Private dependencies og Actions

Auth krever lesetilgang til BK-Teisrud/SwiftNetworking. Gi utviklere og appenes buildsystemer nødvendig tilgang. Under repositoryets Settings → Secrets and variables → Actions opprettes NETWORKING_READ_TOKEN med minst mulig lesetilgang til dette dependency-repositoryet. Workflowene bruker checkout uten vedvarende credentials og en lokal Git-mirror.

Et fork-pull request får normalt ikke repository-secrets og kan derfor ikke forventes å bygge den private dependencyen. Ikke bytt til pull_request_target for å kjøre ukjent kode med et lesetoken; kjør godkjente bidrag i en avtalt intern flyt.

Den ordinære Auth-workflowen bruker Xcode 26.2, simulatornavnet iPhone 17 Pro og GitHub-runner macos-15. Kontroller at disse faktisk finnes på valgt runner. Den manuelle signed macOS Keychain-workflowen trenger en separat self-hosted runner med label auth-keychain og forhåndskonfigurert Apple-signering. Ingen certificates/profiles eller teamhemmeligheter lastes opp i repositoryet.

## Repository-innstillinger

Etter første grønt Actions-bygg kan standardbranchen beskyttes med krav om pull request og den ordinære Auth-testjobben. Tilpass reviewkrav til hvem som faktisk vedlikeholder pakken. Aktiver tilgjengelige sikkerhetsfunksjoner og privat sårbarhetsrapportering der GitHub-planen støtter det. Ikke krev en manuell signeringsjobb på hver pull request; følg i stedet releasekravene i [Release](Release.md).

Den lokale klargjøringen publiserer ingen kode, oppretter ingen GitHub-secrets og bekrefter ikke et grønt Actions-bygg. Sett opp og verifiser disse i det faktiske GitHub-repositoryet før release.
