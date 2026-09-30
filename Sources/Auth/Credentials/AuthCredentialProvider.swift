import Foundation
import Networking

/// One API-client session. Create a new provider after login, restore or logout.
public actor AuthCredentialProvider: CredentialProvider {
  private let client: AuthClient
  private var sessionID: UUID?
  /// Creates a provider that binds on its first successful token acquisition. Create a new one after successful login or restore.
  public init(client: AuthClient) { self.client = client }
  /// Gets a sensitive bearer token and binds the provider to the client's session ID. The binding never changes.
  /// - Throws: `operationInvalidated` after a session change, or an error from ``AuthClient/validAccessToken()``.
  public func bearerToken() async throws -> String {
    let (id, token) = try await client.credential(expectedSession: sessionID)
    guard sessionID == nil || sessionID == id else { throw AuthError.operationInvalidated }
    sessionID = id
    return token
  }
  /// Handles a rejected token within the same bound session. Cannot be used before the first successful token acquisition.
  /// - Throws: `operationInvalidated` for a missing binding or session change; otherwise the client's refresh error.
  public func recover(rejectedToken: String) async throws -> String {
    guard let sessionID else { throw AuthError.operationInvalidated }
    return try await client.recover(rejectedToken: rejectedToken, expectedSession: sessionID)
  }
}
