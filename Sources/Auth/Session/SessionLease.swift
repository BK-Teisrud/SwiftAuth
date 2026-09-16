import Darwin
import Foundation

/// A process-wide lease prevents independent coordinators from sharing a rotating credential.
final class SessionLease: @unchecked Sendable {
  private static let registry = Registry()
  private let key: String
  private let descriptor: Int32
  private init(key: String, descriptor: Int32) {
    self.key = key
    self.descriptor = descriptor
  }
  static func acquire(_ key: String) throws -> SessionLease {
    try registry.lock.withLock {
      guard registry.keys.insert(key).inserted else { throw AuthError.sessionAlreadyInUse }
      do {
        let path = try SessionFiles.directory().appendingPathComponent(key + ".lock").path
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw AuthError.storage }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
          close(descriptor)
          throw AuthError.sessionAlreadyInUse
        }
        return SessionLease(key: key, descriptor: descriptor)
      } catch {
        registry.keys.remove(key)
        throw error
      }
    }
  }
  deinit {
    _ = flock(descriptor, LOCK_UN)
    close(descriptor)
    _ = Self.registry.lock.withLock { Self.registry.keys.remove(key) }
  }
  private final class Registry: @unchecked Sendable {
    let lock = NSLock()
    var keys: Set<String> = []
  }
}
