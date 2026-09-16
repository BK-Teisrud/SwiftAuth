import Foundation

/// Contains only lock files and credential-free logout markers; never tokens or identity.
enum SessionFiles {
  static func directory() throws -> URL {
    do {
      let root = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask,
        appropriateFor: nil, create: true
      ).appendingPathComponent("TeisrudAuth", isDirectory: true)
      var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
      #if os(iOS)
        // A logout marker contains no secret and must remain writable when the device is locked.
        attributes[.protectionKey] = FileProtectionType.none
      #endif
      try FileManager.default.createDirectory(
        at: root, withIntermediateDirectories: true, attributes: attributes)
      return root
    } catch { throw AuthError.storage }
  }
}
