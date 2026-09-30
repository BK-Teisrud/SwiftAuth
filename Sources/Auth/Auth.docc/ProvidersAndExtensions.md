# Providers and extensions

Use hosted connections for sign-in methods behind the same broker. Implement a new ``AuthOIDCAdapter`` only when the OIDC service contract itself changes.

## Hosted providers

Apple, Vipps, email, and SMS are identity-service concerns. ``AuthLoginChoice/connection(_:)`` adds an exact provider-specific query parameter to the authorization request. It does not configure the provider, collect credentials, or verify that a connection exists.

Applications must verify every enabled connection end to end against the real broker and protected API. Never claim provider support based only on compilation or synthetic token tests.

## Adapter contract

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
