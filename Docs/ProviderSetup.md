# Provider and application setup

No live provider, broker, or backend integration is currently claimed as verified. Complete and record this checklist in the integrating application's release process before production use.

## Identity service

1. Register a native public OIDC client. Do not create or embed a client secret.
2. Enable Authorization Code flow with PKCE S256 and RS256 ID tokens.
3. Register every login and post-logout redirect URI exactly, including scheme, host, path, and casing.
4. Publish discovery metadata and JWKS over HTTPS. Endpoints on a different origin require an explicit `trustedEndpointOrigins` entry.
5. Configure the API identifier as either an Auth0-style audience or an RFC 8707 resource, matching `AuthConfiguration`.
6. Enable only the scopes and hosted connections the application uses. A `.connection` value only sends a provider-specific name; it does not create an integration.
7. Confirm refresh-token rotation, replacement-token behavior, lifetime, revocation, and `invalid_grant` behavior.
8. Confirm that refresh ID tokens preserve the original subject and audience contract.

## Application

1. Add Auth and, when constructing `HTTPClient`, Networking through Swift Package Manager.
2. Register the custom callback scheme in URL Types. For HTTPS callbacks, configure Universal Links, Associated Domains, and the AASA file. HTTPS callbacks require iOS 17.4 or macOS 14.4 or later.
3. Use a unique Keychain namespace for every application and environment.
4. Create one shared `AuthClient`, call `restoreSession()` once during startup, and create fresh API clients after a successful restore or login.
5. Mark protected Networking requests with `requiresAuthentication: true`.
6. Cancel account-bound work, clear account caches, and discard late responses when the session changes.
7. Never log authorization URLs, callbacks, codes, tokens, one-time codes, request bodies, or personal data.

## Required integration tests

- Successful, cancelled, and rejected login for every enabled provider or hosted connection.
- Callback mismatch, invalid state, invalid nonce, and expired or malformed tokens.
- Refresh success, rotation, `invalid_grant`, offline behavior, timeout, process termination after possible send, and restart quarantine.
- Logout with available, locked, and failing Keychain storage; process restart with a pending logout marker.
- Account A to account B transition, delayed 401 responses, late responses, and cache isolation.
- Broker-issued access token against the real protected API, including insufficient scope and revoked access.
- Signed Data Protection Keychain behavior on supported macOS and iOS versions.
- Simulator and physical-device coverage for callbacks, browser presentation, app lifecycle, and network changes.

Use synthetic accounts and sanitized evidence. Record the Auth and Networking revisions, operating-system versions, providers tested, backend environment, and known limitations outside this repository. Never store credentials or personal data in test evidence.


## Direct sign-in with your own backend

This is an alternative to the hosted OIDC setup above. No external broker or OIDC discovery service is required. The application supplies a `DirectAuthBackend` implementation and uses `DirectAuthAdapter`.

```swift
let adapter = try DirectAuthAdapter(
    backendURL: URL(string: "https://api.example.com")!,
    applicationID: "com.example.app",
    githubClientID: "public-github-client-id",
    redirectURI: URL(string: "com.example.app://callback")!,
    keychainNamespace: "com.example.app.direct.production",
    backend: appBackend,
    apple: SystemAppleAuthorization(presentationAnchor: { appWindow }),
    browser: SystemAuthBrowser(presentationAnchor: { appWindow })
)
let auth = try await AuthClient(adapter: adapter)
try await auth.login(choice: .connection("apple"))
// Or: try await auth.login(choice: .connection("github"))
```

`appBackend` is the application's implementation, and `appWindow` is its active presentation window. Enable Sign in with Apple for the signed application and register the GitHub OAuth app callback. No email/profile scopes are requested by default. Provider configuration and real-device tests remain required.

GitHub callbacks may include an `iss` parameter. When present, it must match GitHub’s issuer `https://github.com/login/oauth` exactly; callback URL and state validation also remain required. Callbacks without `iss` are supported.

### Required backend work before enabling login

- **Begin:** accept provider, state, Apple nonce or GitHub S256 challenge, and callback. Validate application/provider/callback against a server allowlist. Store a random, expiring, single-use transaction ID bound to all these fields and the registered provider client. Return `DirectAuthTransaction`. Rate-limit transaction creation and exchanges.
- **Apple exchange:** accept transaction ID, authorization code and identity token. Exchange the code on the server using server-held Apple credentials. Verify signature/JWKS, algorithm, issuer, registered audience, expiry, nonce (exact string from begin), and code/token subject consistency. Reject reused or expired transactions. Do not trust client-decoded claims or email.
- **GitHub exchange:** accept transaction ID, authorization code and code verifier. Verify S256 against the stored challenge. Exchange the code with the registered client, server-held secret, exact callback and verifier. Fetch the authenticated GitHub user on the server and use its stable provider ID. Do not accept a user ID or email asserted by the app.
- **Session response:** map the verified provider ID to an internal user, then return `AuthTokenResponse` with issuer equal to the configured backend URL, internal subject, application access token, absolute expiration and optional application refresh token. Nonce/binding must be nil. Provider tokens must not be returned as app tokens.
- **Refresh:** accept the application refresh token over HTTPS, validate its stored hash and expiry, and rotate atomically. Return the same internal identity and a nonempty replacement refresh token. Map a definitively invalid token to `AuthError.refreshRejected`; uncertain network outcomes must remain quarantined. Never automatically retry rotation or exchange.
- **Revocation and account lifecycle:** add server-side session revocation, account deletion, authenticated account linking and recovery policy. Local `AuthClient.logout()` only clears the device session. Invoke the backend revocation operation from the application when needed, and still clear local credentials if it fails.
- **Transport:** use authenticated HTTPS, no credential logging, no credential-bearing redirects, bounded responses/timeouts, and cancellation. Validate responses before returning them from the backend implementation; map failures to redacted `AuthError` values.

Endpoint paths and serialization are intentionally left to the existing backend. This checklist is the integration contract to implement when backend work starts. Use a new Keychain namespace for direct sessions so older broker sessions cannot be restored into this adapter. Verify both providers, transaction replay rejection, refresh rotation, revocation and API authorization end to end before release.
