# Architecture

The package keeps native authorization, browser presentation, provider/backend exchange, OIDC protocol work, session coordination, persistence, and API credentials behind explicit ownership boundaries.

## Ownership

- ``AuthClient`` owns session state, operation generations, refresh sharing, persistence commits, and public lifecycle operations.
- ``DirectAuthAdapter`` owns direct state/nonce/PKCE creation, callback validation and exchange orchestration.
- ``SystemAppleAuthorization`` owns native Apple authorization presentation and cancellation on MainActor.
- The application implementation of ``DirectAuthBackend`` owns authenticated HTTPS transport; the server verifies provider evidence and owns users, sessions, rotation and revocation.
- ``NativeOIDCAdapter`` owns PKCE creation, browser operations, and the native OIDC flow.
- The internal OIDC service actor owns discovery, endpoint trust, token exchange, JWKS caching, signature validation, and claim validation outside MainActor.
- ``SystemAuthBrowser`` owns one `ASWebAuthenticationSession` and remains on MainActor.
- ``AuthCredentialProvider`` binds a SwiftNetworking credential boundary to one session identity.
- ``AuthSessionObserver`` mirrors token-free state for Observation on MainActor.
- Keychain storage owns credentials; session files own only the process lock and credential-free logout marker.

## Commit ordering

Login and refresh validate the complete response before mutation. A replacement refresh token is persisted before its access token is published. Logout clears memory and invalidates operations before durable cleanup, while the logout marker prevents a later process from silently restoring credentials after failed deletion.

Operation generations stop late work from mutating a newer state. A separate session identity prevents old API clients from acquiring credentials after restore, login, logout, or account change.

## Concurrency

`AuthClient` and the OIDC service are actors. Browser and observation types are MainActor-bound. Keychain calls remain synchronous inside the actor so no suspension occurs between generation checks and persistence commits. One refresh task is shared per session.

## Extension points

``AuthOIDCAdapter`` is the trusted session boundary for hosted OIDC and direct backend adapters, ``DirectAuthBackend`` is the application backend boundary, ``DirectAppleAuthorization`` is the native Apple boundary, ``AuthBrowserSession`` is the browser boundary, and SwiftNetworking transport is the network boundary. These are trusted extensions and must preserve all documented validation, privacy, cancellation, and response-limit guarantees.

Keep domain models, screens, navigation, backend authorization, account caches, and application lifecycle coordination outside this package.

## Documentation maintenance

Update public Swift comments, DocC guides, tests, and provider integration guidance together when a contract changes. Keep public documentation in English. Do not add generated documentation, analysis reports, internal findings, machine-specific files, or standalone maintenance-policy Markdown files to the repository.
