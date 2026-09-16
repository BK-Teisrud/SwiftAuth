# Integrasjon med Networking og andre nettverksbehov

Bruk riktig API-token og behold kontotilhørighet gjennom forespørselens levetid.

## Opprett API-klienten

```swift
import Auth
import Foundation
import Networking

func makeProtectedAPI(auth: AuthClient, baseURL: URL) throws -> HTTPClient {
  HTTPClient(configuration: try ClientConfiguration(
    baseURL: baseURL,
    credentialProvider: AuthCredentialProvider(client: auth)
  ))
}
```

Binder du provider til feil API, kan token sendes til feil server. Én AuthConfiguration dekker én API-resource. Bruk bare den tilhørende API-klienten; ikke distribuer samme bearer til vilkårlige tredjeparts-URL-er.

## REST/JSON

```swift
struct Profile: Decodable, Sendable {
  let displayName: String
}

func loadProfile(api: HTTPClient) async throws -> Profile {
  let response = try await api.decode(
    HTTPRequest(pathSegments: ["profile"], requiresAuthentication: true),
    as: Profile.self
  )
  return response.value
}
```

Auth kjenner ikke datamodellen eller HTTP-paths. Networking eier requestbygging, sending, svar og replay-policy; Auth eier credentials. Requesten må eksplisitt være requiresAuthentication. Ubeskyttede requests skal ikke automatisk få token fordi klienten har provider.

## Sesjonsbundet provider

AuthCredentialProvider binder seg ved første vellykkede bearerToken-kall. Før dette kan den opprettes under appoppstart uten å utløse nettverk. Bindingen endres aldri automatisk.

| Hendelse | Eksisterende bundet provider |
| --- | --- |
| Refresh/rotasjon i samme sesjon | Fortsatt gyldig. |
| Forsinket 401 for tidligere utlevert token i samme sesjon | Gjenbruker nyere token eller deler én refresh. |
| Vellykket login som annen bruker | Ugyldig; gamle requests kan ikke bruke ny bruker. |
| Vellykket login som samme bruker/samme tokenstreng | Fortsatt ny sesjon; gammel provider er ugyldig. |
| restoreSession | Ny sesjons-ID; opprett ny provider etter avklart restore. |
| Feilet/avbrutt login | Gammel binding beholdes når gammel lokal sesjon beholdes. |
| Logout | Binding invalideres, også når sletting feiler. |

Ny provider skal ikke installeres i en gammel pågående operasjon for å få den til å lykkes. La gamle operasjoner feile, og start nye brukerhandlinger mot den nye API-klienten. Del én provider mellom API-klienter bare for samme sesjon og riktig resource.

Direkte AuthClient.recover krever et faktisk tidligere utlevert tokenfingeravtrykk. Den bounded historikken er ikke en liste som appen skal fylle med egne tokens. Ved session-sensitive integrasjon bruk AuthCredentialProvider, som også skiller samme tokenstreng mellom ulike logins.

## 401 og replay

Networking kan forsøke én credential recovery når requestens replay-policy tillater det og sendbudsjettet har plass. GET/HEAD er normalt replaybare; andre metoder krever en eksplisitt trygg serverkontrakt. En idempotency key alene bekrefter ikke replay-sikkerhet. Auth gir ikke ubegrenset retry, og refresh-tokenrequesten retryes ikke automatisk.

Networking mapper providerfeil til sin AuthenticationError/providerFailure. Direkte Auth-kall gir AuthError. Observer aktuell AuthState og håndter egen request-livssyklus; en gammel providers operationInvalidated skal ikke endre navigasjonen til den nye innloggede brukeren.

## Fil- og bildeoverføring

Auth leverer bare API-credentials. Networking sin request preparation kan hente bearer før en transfer; transferens cancellation, fremdrift, bakgrunnsrettigheter og eventuell restart håndteres av transferlaget/appens serverkontrakt. Foreground-transfers har ikke automatisk 401-recovery/replay. Start på nytt bare når fil/body og serverkontrakten tåler det.

For signerte upload-URL-er kan autentisering ligge i selve serverutstedte kontrakten. Ikke legg API-bearer til en annen origin uten uttrykkelig avtale. Filjobs må være knyttet til brukeren som opprettet dem; logout betyr ikke at OS allerede har stoppet alle bakgrunnsoverføringer.

## Chat og realtime

Hent credential gjennom en provider som tilhører riktig sesjon når forbindelsen etableres. Auth implementerer ikke WebSocket/SSE, subscriptions, meldingseksakt-en-gang eller reconnect. Avklar om serveren krever header ved handshake, en separat autentiseringsmelding eller reconnect ved tokenutløp.

Ikke gjenbruk en etablert konto-A-kanal etter login som B. Koble ned og opprett ny provider/forbindelse. Tokenrotasjon i samme sesjon er ikke automatisk en endring av realtime-kanalens server-side autorisasjon.

## Offline og bakgrunnsarbeid

Lokal identitet kan brukes til å velge kontoens cache mens appen er offline. Det betyr ikke at API-kall lykkes uten gyldig token/nettverk. Auth har ikke en offline-database, syncmotor eller jobbkø.

WhenUnlockedThisDeviceOnly kan være utilgjengelig ved låst enhet. Ikke svekk Keychain-tilgangen for å få en bakgrunnsjobb til å lykkes. Utsett arbeidet eller håndter utilgjengelig lagring etter appens behov. Brukerens jobbkøer må ha konto-ID og må ikke replayes som en senere innlogget bruker.

## Tredjepartsintegrasjoner

Et annet API med annen audience krever egen avklart token/resource-kontrakt. Første versjon har ikke multi-resource token exchange eller credentialdeling mellom apper. Ikke bruk ID-token som API-token, og ikke send client secrets fra en native app.
