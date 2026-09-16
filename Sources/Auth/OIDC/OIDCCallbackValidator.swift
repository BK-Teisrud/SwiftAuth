import Foundation

struct OIDCCallbackValidator: Sendable {
  let issuer: URL
  func fields(_ callback: URL, expected: URL, state: String) throws -> [String:
    String]
  {
    guard callback.absoluteString.utf8.count <= 16384,
      let actual = URLComponents(url: callback, resolvingAgainstBaseURL: false),
      let target = URLComponents(url: expected, resolvingAgainstBaseURL: false),
      actual.scheme == target.scheme, actual.host == target.host, actual.port == target.port,
      actual.percentEncodedPath == target.percentEncodedPath, actual.fragment == nil,
      actual.user == nil, actual.password == nil
    else { throw AuthError.callback }
    var fields: [String: String] = [:]
    for item in actual.queryItems ?? [] {
      guard fields[item.name] == nil, let value = item.value else { throw AuthError.callback }
      fields[item.name] = value
    }
    guard fields["state"] == state,
      fields["iss"] == nil || fields["iss"] == issuer.absoluteString,
      !(fields["code"] != nil && fields["error"] != nil)
    else { throw AuthError.callback }
    return fields
  }
}
