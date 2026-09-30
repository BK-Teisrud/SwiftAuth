# Offentlig GitHub-oppsett

Auth distribueres fra det offentlige repositoryet `BK-Teisrud/SwiftAuth`. Offentlig lesetilgang gir ikke bruks-, endrings- eller distribusjonsrettigheter; [LICENSE](../LICENSE) beholder alle rettigheter hos Teisrud Development AS.

## Publisert innhold

Commit Package.swift, Sources, Tests, Docs, README, Examples, LICENSE, AGENTS.md, CONTRIBUTING.md, SECURITY.md og GitHub-/Git-konfigurasjonen. Behold eksempelappens shared scheme, entitlements og Package.resolved; de er del av reproducerbar appintegrasjon. Rotens library-lockfile ignoreres fordi Networking er låst til en eksakt SemVer-release i manifestet.

.gitignore utelater SwiftPM-cache, Xcode-brukerdata, bygg/test-/coveragefiler, generert DocC, lokale miljøfiler og private signeringsfiler. .gitattributes normaliserer tekst til LF og markerer binære filer. Ignore-regler gjelder ikke filer som allerede er sporet. Kontroller derfor alltid historikk, Git-status og staged innhold før publisering. Analyserapporter skal aldri opprettes eller lastes opp.

SwiftNetworking er offentlig og krever ingen dependency-secret. Ikke legg tokens i package-URL-er, Git-remotes, Actions eller appkonfigurasjon. Bruk aldri `pull_request_target` til å kjøre ukjent bidragskode med forhøyede rettigheter.

## Repository-innstillinger

- Actions tillater bare GitHub-eide actions og krever full commit-SHA. Workflow-token har read-only standardrettigheter og kan ikke godkjenne pull requests.
- `main` krever pull request, lineær historikk, løste reviewtråder og grønne statuskontroller for minimumsbygg, gjeldende macOS-testsuite og iOS. Force-push og sletting er blokkert.
- Alle tags er beskyttet mot force-update og sletting.
- Merge commits er deaktivert; squash og rebase er tillatt. Brancher slettes etter merge.
- Dependabot security updates, dependency graph, secret scanning, push protection og private vulnerability reporting er aktivert.
- Issues er aktivert; wiki, projects og discussions er deaktivert.

Den manuelle signed macOS Keychain-workflowen kjører bare på en forhåndskonfigurert self-hosted runner merket `auth-keychain`. Ingen sertifikater, profiler, team-ID-er eller secrets ligger i repositoryet. Jobben er et eksplisitt releasekrav, men skal ikke kjøre vilkårlig pull request-kode.

## Tags og releases

Release-tags peker på gjennomgåtte commits og flyttes aldri. Før release skal CI være grønn, dokumentasjonen samsvare med faktisk funksjon, og release notes oppgi eksakt Networking-versjon og hvilke live integrasjoner som faktisk er verifisert. Manglende provider-, backend-, fysisk enhet- eller signert Keychain-verifikasjon skal stå eksplisitt; en offentlig SemVer-release er ikke i seg selv produksjonsgodkjenning.
