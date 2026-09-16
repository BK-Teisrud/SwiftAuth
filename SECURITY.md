# Sikkerhet

## Rapportering

Rapporter sårbarheter privat til repositoryeieren eller Teisrud Development AS gjennom en allerede avtalt privat kontaktkanal. Bruk GitHubs private rapportering hvis funksjonen er aktivert for repositoryet. Ikke legg sensitive detaljer i offentlige issues eller pull requests.

Oppgi berørt revisjon, plattform, forventet/faktisk oppførsel og en minimal reproduksjon med syntetiske data. Ikke send ekte access-/refresh-/ID-tokens, authorization codes, OTP, brukerdata eller klienthemmeligheter.

## Vedlikehold og utgivelser

Ingen utgivelsesversjon eller støtteperiode er etablert før en faktisk release er publisert. Produksjonsintegrasjoner skal bruke en godkjent revisjon eller release og følge endringer i sikkerhetskritiske kontrakter.

[Sikkerhetsdokumentasjonen](Sources/Auth/Auth.docc/Security.md) beskriver implementerte kontroller og begrensninger. [Utgivelsesveiledningen](Docs/Release.md) beskriver nødvendige live tester og separat sikkerhetsgjennomgang. Et grønt bygg alene bekrefter ikke en sikker provider- eller backendintegrasjon.
