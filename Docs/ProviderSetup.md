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
