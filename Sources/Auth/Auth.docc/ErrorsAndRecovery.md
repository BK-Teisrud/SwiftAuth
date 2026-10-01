# Errors and recovery

``AuthError`` exposes stable categories and a conservative ``AuthRecoveryAction`` without embedding provider responses, URLs, codes, tokens, or personal data.

## Recovery actions

| Action | Application response |
| --- | --- |
| `retry` | Retry only after a transient pre-send network or service failure |
| `signIn` | Ask the user to start a new explicit login |
| `configure` | Correct application, provider, callback, issuer, or trust configuration |
| `waitForStorage` | Wait for Keychain or file storage and retry the blocked storage operation |
| `none` | Handle cancellation, concurrency, or stale-session work without automatic retry |

The action is guidance; it never performs login, retry, or logout.

## Important categories

- `invalidConfiguration`, `discovery`, and `unsupportedProviderFeature` require reviewed configuration or provider capabilities.
- `callback`, `tokenExchange`, and `idTokenValidation` indicate protocol validation failure. Do not accept partial identity.
- `networkUnavailable` is limited to failures known to occur before a refresh credential could be sent.
- `serviceUnavailable` represents a service-side failure with no raw response exposed.
- `refreshRejected` requires new login, including `invalid_grant`.
- `refreshOutcomeUnknown` means refresh may have been sent and rotated. The credential remains quarantined; do not retry it.
- `operationInvalidated` protects a later session from stale operations or unknown rejected tokens.
- `keychain`, `storage`, and `logoutPersistenceUnavailable` require explicit storage handling; absence must not be inferred from an availability failure.

## Direct backend errors

The application's ``DirectAuthBackend`` implementation must map HTTP and decoding failures to redacted ``AuthError`` values. Use `refreshRejected` only for a definitive invalid/expired application refresh token. Never retry a possibly sent exchange or refresh automatically; uncertain refresh outcomes remain quarantined. Direct login rejects unknown provider choices, invalid callback/state, malformed application sessions and stale operation results. Apple cancellation produces `cancelled`.

## Networking mapping

SwiftNetworking wraps credential-provider failures in `AuthenticationError.providerFailure`. Use the Auth state stream for the current structured cause. A delayed API failure must never log out or refresh a newer session.

## Logging

Error cases, recovery actions, and numeric OSStatus values may be used for controlled diagnostics. Do not attach callback URLs, authorization URLs, request or response bodies, JWTs, bearer tokens, refresh tokens, authorization codes, PKCE values, one-time codes, email addresses, phone numbers, or provider error descriptions.
