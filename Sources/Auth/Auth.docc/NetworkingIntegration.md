# Networking integration

Bind SwiftNetworking credentials to exactly one Auth session and make authentication explicit on each protected request.

## Create a session-bound client

```swift
let provider = AuthCredentialProvider(client: auth)
let api = HTTPClient(configuration: try ClientConfiguration(
    baseURL: URL(string: "https://api.example.com/")!,
    credentialProvider: provider
))
```

The provider binds permanently on its first successful token acquisition. A successful restore or login creates a new session identity, so replace the provider and `HTTPClient` afterward. Do not reuse an old provider for another account or a new session belonging to the same account.

## Protected requests

```swift
let account = try await api.decode(
    HTTPRequest(
        pathSegments: ["v1", "account"],
        requiresAuthentication: true
    ),
    as: AccountDTO.self
)
```

Networking never infers that a request is protected. Only requests with `requiresAuthentication: true` receive the access token. The token is treated as an opaque bearer credential; Auth never sends an ID token to the API.

## Rejection and recovery

Networking may call the provider once after a rejected token. Auth reuses a newer token from the same session or coordinates refresh. Unknown tokens, old sessions, and delayed failures are rejected with `operationInvalidated`; they are never replayed with credentials from a later account.

Networking wraps provider failures in its own `AuthenticationError`. Observe ``AuthClient/state`` for the structured Auth reason and required user action. Direct Auth calls throw ``AuthError``.

## Application responsibilities

- Use a dedicated client for the intended protected API.
- Cancel account-bound requests and discard late results during logout or account changes.
- Clear or partition caches by stable issuer-plus-subject identity.
- Keep request and response diagnostics free of tokens and personal data.
- Verify backend scopes, authorization, revocation, and tenancy independently of successful OIDC login.

File transfer, realtime, offline queues, and background work must follow the same account-generation rule. Auth supplies credentials; it does not own those operations or their application lifecycle.
