import Foundation
import Networking

/// One API-client session. Create a new provider after login, restore or logout.
public actor AuthCredentialProvider: CredentialProvider {
  private let client: AuthClient
  private var sessionID: UUID?
  /// Oppretter en provider som bindes ved første vellykkede tokenanskaffelse. Lag en ny etter vellykket login eller restore.
  public init(client: AuthClient) { self.client = client }
  /// Henter sensitivt bearer-token og binder provideren til klientens sesjons-ID. Bindingen endres aldri.
  /// - Throws: `operationInvalidated` ved sesjonsbytte eller feil fra ``AuthClient/validAccessToken()``.
  public func bearerToken() async throws -> String {
    let (id, token) = try await client.credential(expectedSession: sessionID)
    guard sessionID == nil || sessionID == id else { throw AuthError.operationInvalidated }
    sessionID = id
    return token
  }
  /// Håndterer et avvist token innenfor samme bundne sesjon. Kan ikke brukes før første vellykkede tokenanskaffelse.
  /// - Throws: `operationInvalidated` ved manglende binding eller sesjonsbytte; ellers klientens refresh-feil.
  public func recover(rejectedToken: String) async throws -> String {
    guard let sessionID else { throw AuthError.operationInvalidated }
    return try await client.recover(rejectedToken: rejectedToken, expectedSession: sessionID)
  }
}
