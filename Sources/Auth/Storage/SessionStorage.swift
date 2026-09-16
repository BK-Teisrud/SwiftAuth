import Foundation
import Security

struct StoredSession: Codable, Sendable, Equatable {
  let identity: AuthIdentity
  let refreshToken: String
  let loginNonce: String?
  let idTokenBinding: AuthIDTokenBinding?
  let version: Int
  let refreshRejected: Bool
  let refreshInFlight: Bool
  init(
    identity: AuthIdentity, refreshToken: String, refreshInFlight: Bool = false,
    refreshRejected: Bool = false, loginNonce: String? = nil,
    idTokenBinding: AuthIDTokenBinding? = nil
  ) {
    self.identity = identity
    self.refreshToken = refreshToken
    self.loginNonce = loginNonce
    self.idTokenBinding = idTokenBinding
    self.refreshInFlight = refreshInFlight
    self.version = 1
    self.refreshRejected = refreshRejected
  }
}

/// Synchronous persistence deliberately prevents actor reentrancy between generation check and Keychain commit.
protocol SessionStorage: Sendable {
  func load() throws -> StoredSession?
  func save(_ session: StoredSession) throws
  func remove() throws
  func hasPendingLogout() throws -> Bool
  func markLogoutPending() throws
  func clearPendingLogout() throws
}

struct KeychainSessionStorage: SessionStorage {
  let service: String
  private var logoutMarker: URL {
    get throws { try SessionFiles.directory().appendingPathComponent(service + ".logout") }
  }
  func hasPendingLogout() throws -> Bool {
    do {
      let marker = try Data(contentsOf: logoutMarker)
      guard marker == Data([1]) else { throw AuthError.storage }
      return true
    } catch CocoaError.fileReadNoSuchFile { return false } catch { throw AuthError.storage }
  }
  func markLogoutPending() throws {
    do {
      #if os(iOS)
        try Data([1]).write(to: logoutMarker, options: [.atomic, .noFileProtection])
      #else
        try Data([1]).write(to: logoutMarker, options: .atomic)
      #endif
    } catch { throw AuthError.storage }
  }
  func clearPendingLogout() throws {
    do {
      if try hasPendingLogout() { try FileManager.default.removeItem(at: logoutMarker) }
    } catch { throw AuthError.storage }
  }
  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrAccount as String: "session", kSecAttrSynchronizable as String: false,
    ]
  }
  func load() throws -> StoredSession? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw AuthError.keychain(status: status) }
    guard let data = result as? Data else { throw AuthError.storage }
    do { return try JSONDecoder().decode(StoredSession.self, from: data) } catch {
      throw AuthError.storage
    }
  }
  func save(_ session: StoredSession) throws {
    let data: Data
    do { data = try JSONEncoder().encode(session) } catch { throw AuthError.storage }
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw AuthError.keychain(status: status) }
  }
  func remove() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw AuthError.keychain(status: status)
    }
  }
}
