# Public API reference

Use this page as a map of the public surface. The symbol pages generated from Swift declarations contain exact signatures and availability.

## Configuration

- ``AuthConfiguration`` defines one issuer, public client, callback, API resource, local namespace, timeout, login choices, trusted endpoint origins, and trusted ID-token audiences.
- ``AuthLoginChoice`` selects a hosted service choice or connection. The direct adapter accepts `.connection("apple")` and `.connection("github")` only.
- ``AuthAPIResource`` sends either an Auth0-style audience or an RFC 8707 resource parameter.

## Session

- ``AuthClient`` restores, signs in, cancels interactive login, supplies valid access tokens, recovers from rejected tokens, logs out locally, and optionally opens provider logout.
- ``AuthState`` provides token-free lifecycle state.
- ``AuthIdentity`` is the stable issuer-plus-subject identity.
- ``AuthSessionObserver`` mirrors client state for Observation on MainActor.

## Networking

- ``AuthCredentialProvider`` conforms to SwiftNetworking's credential-provider boundary and binds permanently to one Auth session.

## OIDC and extension points

- ``NativeOIDCAdapter`` is the production Authorization Code, PKCE, discovery, and RS256 implementation.
- ``AuthOIDCAdapter`` is the trusted session boundary for validated OIDC or backend-issued application sessions.
- ``AuthTokenResponse`` carries sensitive validated adapter output and always redacts its textual description.
- ``AuthIDTokenBinding`` preserves verified audience and authentication-time claims across refresh and restart.
- ``AuthBrowserSession`` abstracts browser presentation for testing.
- ``SystemAuthBrowser`` presents `ASWebAuthenticationSession` in production.

## Errors

- ``AuthError`` defines stable failure categories without raw provider data.
- ``AuthRecoveryAction`` suggests retry, sign-in, configuration repair, storage waiting, or no automatic action.

See <doc:Configuration>, <doc:SessionLifecycle>, <doc:ProvidersAndExtensions>, and <doc:ErrorsAndRecovery> for behavioral contracts and defaults.


## Direct sign-in

- ``DirectAuthAdapter`` connects direct Apple/GitHub authorization to application-owned backend sessions.
- ``DirectAuthBackend`` defines transaction creation, verified exchange and refresh without assuming API endpoints.
- ``DirectAuthProvider``, ``DirectAuthTransaction`` and ``DirectAuthProof`` describe the provider exchange.
- ``DirectAppleAuthorization`` is the injectable native boundary; ``SystemAppleAuthorization`` is its production implementation.

See <doc:ProvidersAndExtensions> and `Docs/ProviderSetup.md` for required backend verification and setup.
