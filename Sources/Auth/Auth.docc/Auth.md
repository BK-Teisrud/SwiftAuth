# ``Auth``

Build direct Apple/GitHub or hosted OIDC sign-in, secure local sessions, and session-bound API credentials without embedding provider secrets or login UI in the package.

## Overview

Auth is a Swift 6 library for iOS 17+ and macOS 14+. It implements Authorization Code with PKCE S256, OIDC discovery, RS256 ID-token validation, Keychain-backed refresh credentials, coordinated refresh, explicit logout, and a SwiftNetworking credential adapter.

Auth supports direct Apple and GitHub authentication with your own backend through ``DirectAuthAdapter``. ``SystemAppleAuthorization`` presents native Sign in with Apple; GitHub uses the system browser with PKCE. Your backend verifies provider evidence and issues application sessions. Hosted OIDC remains available through ``NativeOIDCAdapter``. See <doc:ProvidersAndExtensions>.

Auth uses Foundation, AuthenticationServices, Security, CryptoKit, and SwiftNetworking. It has no third-party identity SDK, JWT library, DesignSystem dependency, application navigation, or prebuilt screen.

> Important: No live provider or backend integration is currently claimed as verified. Synthetic signed-token tests verify protocol code, not a production provider configuration.

## Topics

### Start here

- <doc:GettingStarted>
- <doc:Configuration>
- <doc:SessionLifecycle>

### Integrate and extend

- <doc:NetworkingIntegration>
- <doc:ProvidersAndExtensions>
- <doc:ErrorsAndRecovery>

### Security and maintenance

- <doc:Security>
- <doc:Architecture>
- <doc:TestingAndRelease>
- <doc:APIReference>

### Core API

- ``AuthClient``
- ``AuthConfiguration``
- ``AuthState``
- ``AuthError``
- ``AuthSessionObserver``
- ``AuthCredentialProvider``
- ``NativeOIDCAdapter``
- ``AuthOIDCAdapter``
- ``SystemAuthBrowser``
