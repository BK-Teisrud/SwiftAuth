# Security and privacy

Auth fails closed across protocol validation, endpoint trust, credential persistence, refresh rotation, and account changes.

## OIDC and cryptography

PKCE verifier, state, and nonce use `SecRandomCopyBytes`. SHA-256 uses CryptoKit. RSA signature verification uses `SecKeyVerifySignature`; Auth implements no cryptographic primitive.

The current policy accepts only RS256 and RSA keys from 2048 through 8192 bits. It rejects `none`, unsupported algorithms, duplicate or ambiguous key identifiers, selected JWKs containing private material, unsupported critical headers, malformed base64url, duplicate JSON keys, oversized values, and signature failures.

Validated claims include issuer, non-empty subject, audience, required `azp` rules, `exp`, `iat`, optional `nbf`, login nonce, and optional `at_hash`. There is no clock leeway. Refresh ID tokens are checked against the original subject, audience set, nonce, and optional authentication time.

## Discovery and endpoints

Discovery must advertise authorization code flow, PKCE S256, and RS256. Endpoints require HTTPS, no embedded credentials, no fragments, and a trusted origin. Issuer origin is trusted by default; cross-origin endpoints require an explicit allowlist entry.

Static endpoint query values are preserved only when they do not collide with Auth-owned protocol fields. Redirect handling and response limits are enforced by the OIDC service and trusted transport boundary.

JWT, discovery, and token responses are limited to 64 KiB. JWKS is limited to 256 KiB. Positive `expires_in` is capped at one year.

## Storage

Only the refresh token, minimal issuer-plus-subject identity, original nonce and claim binding, refresh quarantine, and required metadata are persisted. Access and ID tokens are memory-only.

Keychain accessibility is `WhenUnlockedThisDeviceOnly`; synchronization and shared access groups are disabled. Data Protection Keychain is requested explicitly on macOS. Availability errors do not mean that a record is absent. Keychain data may survive application removal.

Logout uses an atomic credential-free marker before Keychain deletion. The marker blocks restore and login until deletion succeeds. No implementation can promise durable logout if both marker storage and Keychain deletion fail, so the failure remains explicit.

## Refresh rotation

A durable in-flight marker is written immediately before the refresh credential may be sent. After that point, timeout, cancellation, process death, or persistence failure can produce an unknown server outcome. Auth quarantines the refresh token and requires login instead of attempting unsafe automatic reuse.

## Account isolation

Session generations reject late login and refresh results. Session-bound credential providers reject delayed 401 recovery across account changes. Applications remain responsible for cancelling old operations, partitioning caches, and dropping late responses.

## Sensitive data

Auth has no diagnostic token logging. Errors do not retain raw provider bodies, URLs, authorization codes, PKCE values, tokens, or personal data. Integrating applications must apply the same rule to analytics, crash reporting, request logging, and test evidence.

## Out of scope

Auth does not provide certificate pinning, token revocation, backend authorization, encrypted application databases, compromised-device protection, cross-application credential sharing, or provider-specific account-linking policy. Review those concerns in the integrating application and service.
