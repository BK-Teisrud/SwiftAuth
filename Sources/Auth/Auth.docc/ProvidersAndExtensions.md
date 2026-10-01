# Providers and extensions

Use ``DirectAuthAdapter`` for Apple and GitHub with your own backend, or hosted connections for sign-in methods behind an OIDC service.

## Direct providers and backend sessions

``SystemAppleAuthorization`` presents native Sign in with Apple. GitHub authorization opens `https://github.com/login/oauth/authorize` in ``SystemAuthBrowser`` with random state and S256 PKCE. Provider credentials are unverified evidence until ``DirectAuthBackend/exchange(_:)`` succeeds. Provider tokens never become application API credentials.

The application implements ``DirectAuthBackend`` using its existing API client. The package intentionally does not assume endpoint paths or a JSON format. Backend responses are trusted over authenticated HTTPS; the backend URL identifies the application's issuer and does not need OIDC discovery. ``AuthIdentity/subject`` is the backend's internal user ID. Direct responses must not contain OIDC nonce or binding metadata.

Create ``DirectAuthAdapter`` with the backend URL, application ID, GitHub public client ID, registered callback, environment-specific Keychain namespace, backend implementation, Apple authorizer and system browser. Then create `AuthClient(adapter: adapter)` and call `login(choice: .connection("apple"))` or `login(choice: .connection("github"))`. The default `.serviceSelection` is unsupported for direct login. Existing restore, session observation, refresh quarantine, and ``AuthCredentialProvider`` behavior applies.

The backend must implement single-use login transactions, Apple claim/signature and code verification, GitHub code exchange with the original PKCE challenge, stable provider-to-user mappings, application session issuance, atomic refresh rotation and session revocation. Never identify or link accounts automatically by email. Use local logout even if backend revocation fails; provider logout is unsupported by this adapter. See the concrete integration checklist in `Docs/ProviderSetup.md`.

Direct authorization follows [Apple AuthenticationServices](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidrequest) and [GitHub authorization](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps). No live provider or backend integration is claimed as verified.

## Hosted providers

Apple, Vipps, email, and SMS are identity-service concerns. ``AuthLoginChoice/connection(_:)`` adds an exact provider-specific query parameter to the authorization request. It does not configure the provider, collect credentials, or verify that a connection exists.

Applications must verify every enabled connection end to end against the real broker and protected API. Never claim provider support based only on compilation or synthetic token tests.

## OIDC adapter contract

An adapter returns ``AuthTokenResponse`` only after validating protocol, signatures, and claims. It must:

- use Authorization Code with PKCE for a public client;
- validate callback scheme, host, path, state, issuer, and authorization errors;
- validate JWS algorithm, key selection, signature, issuer, subject, audience, `azp`, expiry, issue time, optional `nbf`, nonce, and optional `at_hash`;
- preserve verified subject, audience, nonce, and authentication-time bindings during refresh;
- avoid automatic retry after a possibly sent rotating refresh token;
- cooperate with task cancellation and reject late results;
- redact credentials and provider payloads from errors and descriptions.

Cryptographic primitives must come from Security or CryptoKit. Do not add a JWT library or provider SDK to bypass this contract.

## Browser boundary

``AuthBrowserSession`` is injectable for deterministic tests. Production login should use ``SystemAuthBrowser`` and `ASWebAuthenticationSession`. Embedded web views are not supported. A browser implementation must finish a pending continuation exactly once and handle cancellation safely.

A shared `SystemAuthBrowser` permits one active operation. Give independently operating clients separate browser instances.

## Transport boundary

`NativeOIDCAdapter` uses SwiftNetworking transport. A custom transport is trusted security infrastructure: it must preserve HTTPS, endpoint-origin, redirect, response-size, timeout, and cancellation behavior. It must not log authorization bodies or responses.

## Provider logout

Provider logout requires discovered `end_session_endpoint` and a registered post-logout redirect URI. A verified ID-token hint exists only in memory. Local logout is separate and must not depend on remote availability.
