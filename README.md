# Auth

Auth is a reusable Swift package for direct Apple/GitHub and hosted OpenID Connect (OIDC) sign-in, secure local sessions, and API credentials. Version 0.2.1 requires Swift 6.0+, iOS 17+, and macOS 14+. The package contains no login screens, application navigation, passwords, client secrets, or DesignSystem dependency.

Auth supports direct Apple and GitHub sign-in with your own backend through `DirectAuthAdapter`, as well as hosted OIDC through `NativeOIDCAdapter`. Direct sign-in requires no external identity broker. Your backend verifies provider evidence and issues application sessions; the package never contains provider secrets. See [direct provider setup](Docs/ProviderSetup.md#direct-sign-in-with-your-own-backend).

**[Read the documentation index](Docs/README.md)** for setup, session behavior, provider boundaries, security, API contracts, and verification.

## Installation

Add `https://github.com/BK-Teisrud/SwiftAuth.git` in Swift Package Manager using version 0.2.1 or later and select the `Auth` product. Auth uses the exact SwiftNetworking 0.3.1 release. Applications that construct `HTTPClient` directly must also add the `Networking` product.

The following configuration is for hosted OIDC. For direct Apple/GitHub, use the [DirectAuthAdapter example](Docs/ProviderSetup.md#direct-sign-in-with-your-own-backend) and supply your application backend implementation.

```swift
import Foundation
import Auth

let configuration = try AuthConfiguration(
    issuer: URL(string: "https://login.example.com/")!,
    clientID: "registered-public-client-id",
    redirectURI: URL(string: "com.example.app://auth/callback")!,
    scopes: ["openid", "offline_access"],
    apiResource: .oauthResource(URL(string: "https://api.example.com")!),
    keychainNamespace: "com.example.app.production"
)
```

No configuration is read automatically from the application's `Info.plist`. The application must register its callback scheme or configure Universal Links and Associated Domains for an HTTPS callback. Never place GitHub credentials, provider secrets, or client secrets in `Package.swift`, application resources, or CI configuration.

## What the package provides

- `DirectAuthAdapter` supports native Apple and GitHub browser authorization followed by your own backend session exchange. `DirectAuthBackend` defines the application integration contract; `SystemAppleAuthorization` presents native Apple authorization.
- `NativeOIDCAdapter` implements Authorization Code with PKCE S256, discovery, and RS256 ID-token validation using Foundation, AuthenticationServices, Security, and CryptoKit.
- `AuthClient` owns restore, interactive login, refresh coordination, cancellation, logout, and token-free observable state.
- `AuthCredentialProvider` connects a session to SwiftNetworking without exposing tokens through application state.
- `KeychainSessionStorage` stores the refresh token and minimal identity with `WhenUnlockedThisDeviceOnly`. Access and ID tokens are never persisted.
- `AuthOIDCAdapter` is the trusted session boundary. OIDC adapters verify tokens locally; the direct adapter relies on authenticated HTTPS backend verification.

The package does not provide direct Vipps SDK integration, a password grant, an email or SMS provider, account linking, roles, backend authorization, token revocation, an encrypted database, multi-resource token exchange, or cross-application credential sharing.

## Security boundaries

PKCE verifiers, state, and nonce use `SecRandomCopyBytes`; SHA-256 uses CryptoKit; RSA signatures use `SecKeyVerifySignature`. Auth contains protocol code but no custom cryptographic primitives or third-party JWT library.

The hosted OIDC implementation accepts RS256 with RSA keys from 2048 through 8192 bits. It rejects unsigned tokens, unsupported algorithms, ambiguous or unknown key identifiers, private key material in a selected JWK, critical JWS extensions, duplicate JSON keys, invalid issuer/subject/audience/`azp`, expired or premature tokens, invalid nonce, and invalid optional `at_hash`. There is no clock leeway.

Hosted OIDC discovery requires authorization code flow, PKCE S256, and RS256. Endpoints must use HTTPS and trusted origins. Token, discovery, and JWT responses are bounded to 64 KiB; JWKS is bounded to 256 KiB. Direct backend transport must apply its own response limits, credential-free diagnostics and redirect policy. The package never logs raw tokens, authorization codes, PKCE material, callback URLs, or personal data.

## Session contract

Create one `AuthClient` for each application configuration, share it across scenes, and call `restoreSession()` explicitly during startup. A process lock rejects another live client using the same storage identity. Application extensions and shared Keychain access groups are not supported.

`login(choice:)` is always interactive and starts only after an explicit user action. API requests never open the browser. `validAccessToken()` returns a valid in-memory token or coordinates one refresh operation. A potentially sent refresh with an unknown outcome is quarantined instead of retried blindly. `logout()` clears memory, invalidates operations, and uses a credential-free durable marker to make Keychain deletion recoverable.

Create a new `AuthCredentialProvider` and `HTTPClient` after each successful login or restore. A provider binds permanently to the first successful session and cannot switch users, even if a later session has the same subject or token value. Applications must also cancel old requests and discard late responses when the account changes.

Protected Networking requests must opt in explicitly:

```swift
let response = try await api.execute(
    HTTPRequest(pathSegments: ["protected"], requiresAuthentication: true)
)
```

`signedIn` means that local session identity exists. It does not prove current backend authorization. The stable identity is issuer plus subject; email and profile data are not primary keys.

## Provider status

No live provider or backend integration is currently claimed as verified. The test suite covers direct GitHub PKCE/callback checks and backend session handling, plus synthetic RSA-signed OIDC tokens using Apple cryptographic APIs. This does not replace testing direct Apple/GitHub, backend verification, any enabled hosted connections, and the protected API in the integrating application on a simulator and physical device. See [Provider setup](Docs/ProviderSetup.md).

## Verification

```sh
swift build
swift test
xcrun swift-format lint --strict --recursive Package.swift Sources Tests
```

CI verifies the minimum Swift 6 production build, the full test suite with the current toolchain, strict formatting, DocC warnings, and iOS package builds and tests. Generic SwiftPM test hosts do not prove Data Protection Keychain entitlements or a provider integration. The integrating application must run signed Keychain and end-to-end provider tests before release.

## Documentation

- [Getting started](Sources/Auth/Auth.docc/GettingStarted.md)
- [Configuration](Sources/Auth/Auth.docc/Configuration.md)
- [Session lifecycle](Sources/Auth/Auth.docc/SessionLifecycle.md)
- [Networking integration](Sources/Auth/Auth.docc/NetworkingIntegration.md)
- [Providers and extensions](Sources/Auth/Auth.docc/ProvidersAndExtensions.md)
- [Errors and recovery](Sources/Auth/Auth.docc/ErrorsAndRecovery.md)
- [Security](Sources/Auth/Auth.docc/Security.md)
- [Architecture](Sources/Auth/Auth.docc/Architecture.md)
- [Public API reference](Sources/Auth/Auth.docc/APIReference.md)
- [Testing and release](Sources/Auth/Auth.docc/TestingAndRelease.md)

The current public API is versioned as 0.2.1. Before 1.0, minor releases may contain source-breaking changes in accordance with Semantic Versioning.

## License and security

See [security reporting](SECURITY.md). Copyright © 2026 Teisrud Development AS. All rights reserved; see [LICENSE](LICENSE).

## Example application

Open [`Examples/ExampleAuthApp/ExampleAuthApp.xcodeproj`](Examples/ExampleAuthApp/ExampleAuthApp.xcodeproj) in Xcode 26.2 or later. The iOS 26.2+ example uses this checkout as a local package dependency and demonstrates direct Apple/GitHub sign-in, session restoration, verified profiles, and logout. Select your own signing team for device runs.

See the [example setup guide](Examples/ExampleAuthApp/README.md) for backend configuration and the optional GitHub test server. No credentials or tunnel binaries are included. The library itself still supports iOS 17+ and macOS 14+.
