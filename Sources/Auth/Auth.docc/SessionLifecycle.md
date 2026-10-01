# Session lifecycle

Auth separates local identity, sensitive credentials, interactive operations, and API-client lifetime.

## Restore

``AuthClient/restoreSession()`` reads the durable session without opening a browser or refreshing over the network. It first completes any pending logout marker. A successful restore creates a new in-process session identity, so the application must construct a new ``AuthCredentialProvider`` and API client.

## Login

``AuthClient/login(choice:)`` is explicit and interactive. Only one interactive operation may run on a client. Hosted OIDC completes PKCE, callback checks, code exchange and token validation before publishing. Direct login completes native Apple or GitHub browser authorization, local state/callback checks and verified backend session exchange before publishing. Call `.connection("apple")` or `.connection("github")` explicitly with the direct adapter. The refresh token is persisted before the access token becomes available.

``AuthClient/cancelLogin()`` cancels native Apple or browser presentation and invalidates late results. A failed or cancelled reauthentication preserves the prior state when that state remains meaningful.

## Access tokens and refresh

``AuthClient/validAccessToken()`` returns an unexpired access token or shares one refresh task among concurrent callers. With a refresh token, early refresh begins at ten percent of the installed lifetime, capped at 60 seconds. Without a refresh token, the access token remains usable until its actual expiry.

Cancellation by one waiter does not cancel a shared refresh needed by other callers. Logout and a new login invalidate the whole operation. Late results cannot install credentials after their generation has changed.

Refresh preparation occurs before the durable in-flight marker is written. Once credential sending may begin, transport failure, timeout, process termination, or persistence failure can make rotation outcome unknown. Auth preserves identity but quarantines the credential and requires explicit login instead of risking blind token reuse.

OIDC `invalid_grant` or a definitive backend rejection mapped to `refreshRejected` also requires a new login. Direct backend refresh requires a nonempty replacement refresh token for the same internal identity. An expired access token is never returned.

## Account changes

Every successful restore or login creates a new session identity, even for the same issuer, subject, or token value. Session-bound providers reject delayed 401 recovery from an older session. Applications must still cancel old requests, reject late responses, and clear account-bound caches.

## Logout

``AuthClient/logout()`` invalidates operations, clears memory, and deletes the Keychain record. Before deletion it writes an atomic credential-free marker in Application Support. A new process must finish deletion before restore or login when that marker remains.

If Keychain deletion fails, in-memory state is signed out but durable credentials may remain. If both marker persistence and credential deletion fail, Auth reports ``AuthError/logoutPersistenceUnavailable``. The application must surface the failure and retry after storage becomes available.

``AuthClient/logoutAtProvider()`` is a separate optional browser operation. It does not delete local state, promise revocation, or guarantee logout from an upstream Apple or Vipps account.

With ``DirectAuthAdapter``, provider logout is unsupported. Revoke application sessions using the backend API when required, then call local logout even if revocation fails.

## State

``AuthState`` never contains tokens. `signedIn` means local identity is known; it does not prove backend authorization. The stable account key is issuer plus subject, never email or profile data.
