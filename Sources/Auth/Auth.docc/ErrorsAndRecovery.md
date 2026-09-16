# Feil og gjenoppretting

Alle AuthError-verdier, foreslåtte apphandlinger og forskjellen mellom retry og ny innlogging.

## Feilmodell

AuthError er Error/Sendable/Equatable og inneholder ingen rå providerbeskrivelser, callback-URL-er, tokens eller authorization codes. Keychain-feil beholder bare OSStatus. Appen oversetter kategoriene til egne tekster og tilgjengelig UI.

| AuthError | Betydning | recoveryAction |
| --- | --- | --- |
| sessionAlreadyInUse | En levende koordinator/lease bruker samme lagringsidentitet. | none |
| invalidConfiguration | Ugyldig konfigurasjon før flyt. | configure |
| networkUnavailable | Retrybar nettverksforutsetning, rå URLSession-feil før usikker refresh eller frist før sending. | retry |
| serviceUnavailable | HTTP 5xx under discovery/første tokenutveksling. | retry |
| providerRejected | Tjenesten avviser første login/tokenutveksling eller browserrespons. | signIn |
| discovery | Ugyldig metadata, issuer, capability eller endpoint-tillit. | configure |
| browserPresentation | Systembrowser kunne ikke presenteres/fullføres som forventet. | retry |
| cancelled | Brukeren/Task avbrøt flyten. | none |
| loginAlreadyInProgress | Interaktiv operasjon/browserstopp opptar klienten/browseren. | none |
| callback | Ugyldig callbackadresse, state, issuer eller duplikate responsfelter. | signIn |
| tokenExchange | Ugyldig tokenrespons/formkontrakt; ingen rå body eksponeres. | signIn |
| idTokenValidation | JWS/JWK/signatur/claims/binding kunne ikke godkjennes, eller JWKS ikke kunne brukes. | signIn |
| keychain(status:) | Apple Security returnerte annen status enn støttet suksess/not-found. | waitForStorage |
| logoutPersistenceUnavailable | Både varig logout-markering og credential-sletting feilet. | waitForStorage |
| storage | Marker/lagringsformat/versjon eller filoperasjon kunne ikke godkjennes. | waitForStorage |
| refreshRejected | Refresh-grant er avvist; ikke bruk gammel credential igjen. | signIn |
| refreshOutcomeUnknown | Refresh kan ha vært sendt/rotert, men utfallet er usikkert. | signIn |
| reauthenticationRequired | Ingen brukbar access-/refresh-vei finnes. | signIn |
| operationInvalidated | Resultat eller API-provider tilhører en tidligere operasjon/sesjon. | none |
| unsupportedProviderFeature | Ikke konfigurert loginvalg/logout eller annen ustøttet adapterkontrakt. | configure |

recoveryAction er en UI-anbefaling, ikke tillatelse til å oppheve karantene. En timeout etter mulig refresh-send skal aldri få automatisk retry av gammel refresh-token fordi appen har en generell retry-knapp.

## Direkte Auth-kall

```swift
do {
  try await auth.login()
} catch let error as AuthError {
  switch error.recoveryAction {
  case .retry: /* Tilby nytt eksplisitt forsøk. */ break
  case .signIn: /* Tilby ny login; ingen automatisk browser. */ break
  case .configure: /* Håndter konfigurasjon/tjenestekompatibilitet. */ break
  case .waitForStorage: /* Vent på lagring og gjenta riktig lokal handling. */ break
  case .none: /* Forkast avbrutt/stale operasjon. */ break
  }
} catch {
  // CancellationError kan forekomme ved tokenforespørsler.
  // Ikke skriv rå feil/payloads til UI eller logger.
}
```

AuthClient kan kaste CancellationError når én ventende tokenrequest kanselleres. Det er ikke et signal om å stoppe den delte refreshen eller logge ut andre konsumenter. Metodene kan også gi operationInvalidated etter logout/ny login selv når den underliggende browseren meldte cancellation.

## Networking-feil

Networking pakker feil fra CredentialProvider inn som AuthenticationError/providerFailure. Ikke forvent å kunne caste API-feilen direkte til AuthError. Les aktuell AuthState for sesjonsproblem og behold requestens konto-/sesjonskontekst.

Et gammelt API-klientkall kan få providerFailure/operationInvalidated mens den nye brukeren er normalt signedIn. Dette skal normalt forkastes som gammel operasjon; ikke logg den nye brukeren ut som følge av gamle requests.

## Lagringsfeil

Feilet restore forblir restoring; appen må håndtere kastet feil. Keychain-utilgjengelighet betyr ikke at elementet mangler. Etter feilet logout er lokal state signedOut med problem, men diskcredential kan finnes. Gjenta logout når lagring er tilgjengelig; ikke lov varig logout før sletting/markering er avklart.

waitForStorage løser ikke automatisk korrupte JSON-/markørfiler eller feil entitlements. OSStatus og signeringsoppsett må undersøkes uten å eksponere credentialdata. Pakken har ingen offentlig API for å redigere karanteneflagg eller importere vilkårlige tokens.

## Når retry er riktig

Gjenta en mislykket forberedelse/restore/sletting når forutsetningen er reparert. Ved ny login gjentas hele browserflyten, ikke gammel authorization code. Etter refreshOutcomeUnknown/refreshRejected starter brukeren ny login. Ingen recoveryAction lover at backend er tilgjengelig eller at provideravtalen er riktig.
