# Rapportering av sikkerhetsproblemer

Ikke legg tokens, private nøkler, authorization codes, PKCE-verifier, OTP, personopplysninger eller detaljer om en urettet sårbarhet i offentlige issues, pull requests eller testlogger.

Rapporter sårbarheter gjennom GitHub Private Vulnerability Reporting under repositoryets Security-fane. Hvis kanalen ikke er tilgjengelig, kontakt repositoryeieren privat før detaljer publiseres.

Oppgi berørt versjon eller commit, plattform, forventet og faktisk oppførsel, en minimal reproduksjon med syntetiske data og mulig konsekvens. Se [sikkerhetskontraktene](Sources/Auth/Auth.docc/Security.md) for pakkens grenser.

Sikkerhetsrettelser prioriteres for den nyeste publiserte 0.x-versjonen. Det gis ingen langsiktig støttegaranti for eldre 0.x-versjoner. [Utgivelsesveiledningen](Docs/Release.md) beskriver nødvendige live tester og separat protokollgjennomgang; et grønt bygg alene bekrefter ikke en sikker provider- eller backendintegrasjon.
