import CoreFoundation
import Foundation
import Security

// Compact JWS/RS256 validation; cryptographic operations are provided by Apple's Security framework.
struct VerifiedIDToken: Sendable {
  let identity: AuthIdentity
  let binding: AuthIDTokenBinding
}

struct IDTokenValidator: Sendable {
  let configuration: AuthConfiguration
  let now: @Sendable () -> Date

  func validate(
    _ token: String, jwks: Data, nonce: String?, identity: AuthIdentity? = nil,
    accessToken: String? = nil, binding: AuthIDTokenBinding? = nil
  ) throws -> AuthIdentity {
    try validateVerified(
      token, jwks: jwks, nonce: nonce, identity: identity,
      accessToken: accessToken, binding: binding
    ).identity
  }

  func validateVerified(
    _ token: String, jwks: Data, nonce: String?, identity: AuthIdentity? = nil,
    accessToken: String? = nil, binding: AuthIDTokenBinding? = nil,
    refresh: Bool = false
  ) throws -> VerifiedIDToken {
    do {
      guard token.utf8.count <= 65536 else { throw AuthError.idTokenValidation }
      let segments = token.split(separator: ".", omittingEmptySubsequences: false)
      guard segments.count == 3 else { throw AuthError.idTokenValidation }
      let header = try object(decode(String(segments[0])))
      let claims = try object(decode(String(segments[1])))
      guard header["alg"] as? String == "RS256", let kid = header["kid"] as? String,
        !kid.isEmpty, kid.utf8.count <= 256, header["crit"] == nil, header["b64"] == nil,
        header["jku"] == nil, header["x5u"] == nil
      else { throw AuthError.idTokenValidation }
      let keys = try object(jwks)["keys"] as? [[String: Any]] ?? []
      let matching = keys.filter { $0["kid"] as? String == kid }
      guard matching.count == 1 else { throw AuthError.idTokenValidation }
      let jwk = matching[0]
      guard jwk["kty"] as? String == "RSA", jwk["alg"] == nil || jwk["alg"] as? String == "RS256",
        jwk["use"] == nil || jwk["use"] as? String == "sig",
        jwk["key_ops"] == nil || (jwk["key_ops"] as? [String])?.contains("verify") == true,
        ["d", "p", "q", "dp", "dq", "qi"].allSatisfy({ jwk[$0] == nil }),
        let n = jwk["n"] as? String, let e = jwk["e"] as? String
      else { throw AuthError.idTokenValidation }
      let modulus = try decode(n)
      let exponent = try decode(e)
      guard modulus.first != 0, modulus.count >= 256, modulus.count <= 1024,
        modulus.first.map({ $0 & 0x80 != 0 }) == true, modulus.last.map({ $0 & 1 == 1 }) == true,
        exponent.first != 0, exponent.count <= 4, exponent.last.map({ $0 & 1 == 1 }) == true,
        exponent.reduce(UInt64(0), { $0 * 256 + UInt64($1) }) >= 3
      else { throw AuthError.idTokenValidation }
      let keyData = der(0x30, integer(modulus) + integer(exponent))
      var error: Unmanaged<CFError>?
      guard
        let key = SecKeyCreateWithData(
          keyData as CFData,
          [
            kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: modulus.count * 8,
          ] as CFDictionary, &error),
        SecKeyIsAlgorithmSupported(key, .verify, .rsaSignatureMessagePKCS1v15SHA256),
        SecKeyVerifySignature(
          key, .rsaSignatureMessagePKCS1v15SHA256,
          Data("\(segments[0]).\(segments[1])".utf8) as CFData,
          try decode(String(segments[2])) as CFData, &error)
      else { throw AuthError.idTokenValidation }
      guard claims["iss"] as? String == configuration.issuer.absoluteString,
        let subject = claims["sub"] as? String, !subject.isEmpty, subject.utf8.count <= 255,
        subject.utf8.allSatisfy({ $0 < 128 })
      else { throw AuthError.idTokenValidation }
      let audiences: [String]
      if let value = claims["aud"] as? String {
        audiences = [value]
      } else if let value = claims["aud"] as? [String], !value.isEmpty {
        audiences = value
      } else {
        throw AuthError.idTokenValidation
      }
      let trustedAudiences = Set([configuration.clientID] + configuration.trustedIDTokenAudiences)
      guard audiences.contains(configuration.clientID),
        audiences.allSatisfy(trustedAudiences.contains),
        Set(audiences).count == audiences.count
      else { throw AuthError.idTokenValidation }
      if audiences.count > 1 || claims["azp"] != nil {
        guard claims["azp"] as? String == configuration.clientID else {
          throw AuthError.idTokenValidation
        }
      }
      let time = now().timeIntervalSince1970
      let expiry = try numericDate(claims["exp"])
      let issued = try numericDate(claims["iat"])
      guard expiry > time, issued <= time, issued < expiry else {
        throw AuthError.idTokenValidation
      }
      if let notBefore = claims["nbf"] {
        guard try numericDate(notBefore) <= time else { throw AuthError.idTokenValidation }
      }
      if !refresh || claims["nonce"] != nil {
        if let nonce {
          guard claims["nonce"] as? String == nonce else { throw AuthError.idTokenValidation }
        } else if refresh, claims["nonce"] != nil {
          throw AuthError.idTokenValidation
        }
      }
      if let hash = claims["at_hash"] {
        guard let expected = hash as? String, let accessToken else {
          throw AuthError.idTokenValidation
        }
        guard
          expected
            == OIDCEncoding.base64(Data(OIDCEncoding.sha256(Data(accessToken.utf8)).prefix(16)))
        else { throw AuthError.idTokenValidation }
      }
      let authenticationTime = try claims["auth_time"].map { try numericDate($0) }
      if let binding {
        guard audiences.sorted() == binding.audiences,
          authenticationTime == nil || authenticationTime == binding.authenticationTime
        else {
          throw AuthError.idTokenValidation
        }
      }
      let result = AuthIdentity(issuer: configuration.issuer.absoluteString, subject: subject)
      guard identity == nil || result == identity else { throw AuthError.idTokenValidation }
      return VerifiedIDToken(
        identity: result,
        binding: binding
          ?? AuthIDTokenBinding(audiences: audiences, authenticationTime: authenticationTime))
    } catch { throw AuthError.idTokenValidation }
  }

  private func numericDate(_ value: Any?) throws -> Double {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      number.doubleValue.isFinite, number.doubleValue >= 0
    else { throw AuthError.idTokenValidation }
    return number.doubleValue
  }
  private func decode(_ value: String) throws -> Data { try OIDCEncoding.decode(value) }
  private func object(_ data: Data) throws -> [String: Any] { try StrictJSON.object(data) }
  private func integer(_ data: Data) -> Data {
    der(0x02, data.first.map { $0 & 0x80 != 0 } == true ? Data([0]) + data : data)
  }
  private func der(_ tag: UInt8, _ body: Data) -> Data {
    var length = body.count
    var bytes: [UInt8] = []
    repeat {
      bytes.insert(UInt8(length & 255), at: 0)
      length >>= 8
    } while length > 0
    return Data([tag])
      + (body.count < 128
        ? Data([UInt8(body.count)]) : Data([0x80 | UInt8(bytes.count)]) + Data(bytes)) + body
  }
}
