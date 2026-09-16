import CryptoKit
import Foundation
import Security

struct OIDCEncoding {
  static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
  static func base64(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(
      of: "/", with: "_"
    ).replacingOccurrences(of: "=", with: "")
  }
  static func decode(_ value: String) throws -> Data {
    guard !value.isEmpty, value.utf8.count <= 262144,
      value.utf8.allSatisfy({
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
          || $0 == 95
      }), value.count % 4 != 1
    else { throw AuthError.idTokenValidation }
    let padded =
      value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
      + String(repeating: "=", count: (4 - value.count % 4) % 4)
    guard let result = Data(base64Encoded: padded), base64(result) == value else {
      throw AuthError.idTokenValidation
    }
    return result
  }
  static func random() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw AuthError.tokenExchange
    }
    return base64(Data(bytes))
  }
}

/// Foundation parses JSON; this scan additionally rejects duplicate keys, including escaped spellings.
struct StrictJSON {
  static func object(_ data: Data) throws -> [String: Any] {
    guard data.count <= 262144,
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw AuthError.idTokenValidation }
    var scanner = Scanner(bytes: Array(data))
    try scanner.value(depth: 0)
    scanner.space()
    guard scanner.index == scanner.bytes.count else { throw AuthError.idTokenValidation }
    return object
  }
  private struct Scanner {
    let bytes: [UInt8]
    var index = 0
    mutating func space() {
      while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }
    mutating func string() throws -> String {
      let start = index
      guard index < bytes.count, bytes[index] == 34 else { throw AuthError.idTokenValidation }
      index += 1
      while index < bytes.count {
        if bytes[index] == 92 {
          index += 2
          continue
        }
        if bytes[index] == 34 {
          index += 1
          return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
        }
        index += 1
      }
      throw AuthError.idTokenValidation
    }
    mutating func value(depth: Int) throws {
      space()
      guard depth < 32, index < bytes.count else { throw AuthError.idTokenValidation }
      let first = bytes[index]
      if first == 34 {
        _ = try string()
        return
      }
      if first == 123 || first == 91 {
        index += 1
        space()
        let end: UInt8 = first == 123 ? 125 : 93
        if index < bytes.count, bytes[index] == end {
          index += 1
          return
        }
        var names: Set<String> = []
        while index < bytes.count {
          if first == 123 {
            let name = try string()
            guard names.insert(name).inserted else { throw AuthError.idTokenValidation }
            space()
            guard index < bytes.count, bytes[index] == 58 else { throw AuthError.idTokenValidation }
            index += 1
          }
          try value(depth: depth + 1)
          space()
          guard index < bytes.count else { throw AuthError.idTokenValidation }
          if bytes[index] == end {
            index += 1
            return
          }
          guard bytes[index] == 44 else { throw AuthError.idTokenValidation }
          index += 1
          space()
        }
        throw AuthError.idTokenValidation
      }
      let start = index
      while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) {
        index += 1
      }
      guard index > start else { throw AuthError.idTokenValidation }
    }
  }
}
