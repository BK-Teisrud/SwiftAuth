import Foundation

/// Safe, structured errors. Provider descriptions, URLs and credentials are never retained here.
public enum AuthError: Error, Sendable, Equatable {
  /// En annen levende klient eller prosess eier samme lagringsidentitet.
  case sessionAlreadyInUse
  /// Konfigurasjonen bryter valideringsreglene; må korrigeres før bruk.
  case invalidConfiguration
  /// Nettverket var utilgjengelig eller refresh-forberedelsen nådde tidsfristen før credentials ble sendt.
  case networkUnavailable
  /// Tjenesten returnerte en midlertidig serverfeil før en trygg retry er utelukket.
  case serviceUnavailable
  /// Tjenesten avviste innlogging; inneholder ingen rå leverandørbeskrivelse.
  case providerRejected
  /// Discovery, metadata eller endpoint-tillit kunne ikke valideres.
  case discovery
  /// Systemnettleseren kunne ikke presenteres eller fullføre som forventet.
  case browserPresentation
  /// Interaktiv autentisering ble avbrutt av bruker eller klient.
  case cancelled
  /// En konkurrerende interaktiv operasjon, nettleserstopp eller uforenlig sesjonsoperasjon pågår.
  case loginAlreadyInProgress
  /// Callback-URL, state, issuer eller autorisasjonsresultat var ugyldig.
  case callback
  /// Tokenresponsen eller kodeutvekslingen er ugyldig; ingen rå tokenrespons beholdes i feilen.
  case tokenExchange
  /// ID-token, signatur, nøkkel eller claims kunne ikke verifiseres.
  case idTokenValidation
  /// Keychain-operasjonen feilet med eksplisitt OSStatus; rå credentials inkluderes aldri.
  case keychain(status: Int32)
  /// Både den varige logout-markøren og sletting feilet. Minnet er tømt, men diskdata kan fortsatt finnes.
  case logoutPersistenceUnavailable
  /// Sesjonsformat, lagringsoperasjon, filmarkør eller lås kunne ikke håndteres sikkert.
  case storage
  /// Tjenesten avviste refresh, eksempelvis med invalid_grant. Ny eksplisitt login kreves.
  case refreshRejected
  /// Refresh kan ha rotert hos tjenesten uten et kjent lokalt resultat. Tokenet settes i vedvarende karantene.
  case refreshOutcomeUnknown
  /// Sesjonen trenger eksplisitt login, eksempelvis fordi et utløpt token ikke kan fornyes.
  case reauthenticationRequired
  /// Operasjonen tilhører en tidligere sesjon eller et ukjent token. Ikke bruk feilen til å logge ut en ny bruker.
  case operationInvalidated
  /// Påkrevd funksjon eller callback-støtte finnes ikke i tjenesten eller på plattformen.
  case unsupportedProviderFeature
}

/// Suggested UI action; a retry never overrides quarantine of an uncertain rotating refresh.
public enum AuthRecoveryAction: Sendable, Equatable {
  /// Foreslå et nytt eksplisitt forsøk når årsaken er løst. Overstyrer aldri refresh-karantene.
  case retry
  /// Tilby ny eksplisitt innlogging. API-tokenanskaffelse starter ikke nettleseren.
  case signIn
  /// Korriger app- eller tjenestekonfigurasjon før nytt forsøk.
  case configure
  /// Vent på tilgjengelig lagring eller rett lagringsfeilen; prøv ufullført lokal logout igjen.
  case waitForStorage
  /// Ingen automatisk handling. Håndter kansellering, konkurranse eller tidligere sesjon i appens flyt.
  case none
}
extension AuthError {
  /// Anbefalt app-/UI-handling for denne feilen. Verdien utfører ingen retry, logout eller innlogging. Se <doc:ErrorsAndRecovery>.
  public var recoveryAction: AuthRecoveryAction {
    switch self {
    case .networkUnavailable, .serviceUnavailable, .browserPresentation: return .retry
    case .refreshRejected, .refreshOutcomeUnknown, .reauthenticationRequired: return .signIn
    case .invalidConfiguration, .discovery, .unsupportedProviderFeature: return .configure
    case .keychain, .storage, .logoutPersistenceUnavailable: return .waitForStorage
    case .cancelled, .operationInvalidated, .loginAlreadyInProgress, .sessionAlreadyInUse:
      return .none
    case .providerRejected, .callback, .tokenExchange, .idTokenValidation: return .signIn
    }
  }
}
