import Foundation
import Security
import Testing

@testable import Auth

@Suite struct KeychainIntegrationTests {
  #if !AUTH_HOSTED_KEYCHAIN_TESTS
    @Test(
      .disabled(
        "Requires a signed consuming-app test host on macOS or iOS with AUTH_HOSTED_KEYCHAIN_TESTS enabled."
      ))
  #else
    @Test
  #endif
  func keychainRoundTripAndNamespaceIsolation() throws {
    let service = "Auth.test." + UUID().uuidString
    let storage = KeychainSessionStorage(service: service)
    let other = KeychainSessionStorage(service: service + ".other")
    defer { try? storage.remove() }
    #expect(try storage.load() == nil)
    let record = StoredSession(
      identity: .init(issuer: "https://issuer.example.com/", subject: "synthetic-user"),
      refreshToken: "synthetic-refresh", loginNonce: "synthetic-nonce",
      idTokenBinding: .init(audiences: ["one"], authenticationTime: 100))
    try storage.save(record)
    #expect(try storage.load() == record)
    var attributes: CFTypeRef?
    let status = SecItemCopyMatching(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: "session",
        kSecUseDataProtectionKeychain as String: true,
        kSecReturnAttributes as String: true,
      ] as CFDictionary, &attributes)
    #expect(status == errSecSuccess)
    #expect(
      (attributes as? [String: Any])?[kSecAttrAccessible as String] as? String
        == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    #expect(try other.load() == nil)
    let updated = StoredSession(identity: record.identity, refreshToken: "synthetic-rotated")
    try storage.save(updated)
    #expect(try storage.load() == updated)
    try storage.remove()
    #expect(try storage.load() == nil)
  }

  @Test func malformedLogoutMarkerFailsClosed() throws {
    let service = "Auth.test." + UUID().uuidString
    let marker = try SessionFiles.directory().appendingPathComponent(service + ".logout")
    defer { try? FileManager.default.removeItem(at: marker) }
    try Data([0]).write(to: marker, options: .atomic)
    #expect(throws: AuthError.storage) {
      try KeychainSessionStorage(service: service).hasPendingLogout()
    }
  }

  @Test func credentialFreeLogoutMarkerSurvivesStorageReplacement() throws {
    let service = "Auth.test." + UUID().uuidString
    let first = KeychainSessionStorage(service: service)
    defer { try? first.clearPendingLogout() }
    try first.markLogoutPending()
    let replacement = KeychainSessionStorage(service: service)
    #expect(try replacement.hasPendingLogout())
    try replacement.clearPendingLogout()
    #expect(try !first.hasPendingLogout())
  }
}
