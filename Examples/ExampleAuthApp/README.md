# SwiftAuth example application

A SwiftUI iOS app demonstrating direct Apple and GitHub sign-in with your own backend. It uses the Auth package from this repository through a local `../..` package reference; no published Auth version needs to be fetched. The library remains independent of the example and supports iOS 17+ and macOS 14+.

## Run

1. Clone this repository and open `Examples/ExampleAuthApp/ExampleAuthApp.xcodeproj` in Xcode 26.2 or later. The example app targets iOS 26.2+.
2. Choose the `ExampleAuthApp` scheme and an iPhone simulator. For a physical device, select your own development team in Signing & Capabilities.
3. Enter your backend's HTTPS URL, application ID (`no.teisrud.ExampleAuthApp` by default), public GitHub OAuth client ID, and optional expected GitHub username. Never put a client secret in the app.
4. Register `exampleauthapp://auth/callback` in your GitHub OAuth app and allow that callback and application ID on the backend.
5. For Apple, enable Sign in with Apple for your registered app identifier and use a provisioning profile with that capability. The example includes the entitlement, but the optional test backend supports GitHub only.
6. Choose Apple or GitHub. After sign-in, the app fetches the backend profile and compares its internal subject with the authenticated session. An expected GitHub username can also be checked.

Use the settings button at the top right to inspect connection details and choose **Endre tilkobling** to edit them. The interface is in Norwegian, with a dark theme, lime accents, an identity illustration, a profile card, and a matching app icon.

Settings are saved in UserDefaults. SwiftAuth stores session credentials in Keychain. Logout attempts server-side revocation and clears the local session even if the server request fails; revocation failures are shown explicitly. No provider logout is performed. Unsigned simulator builds can compile successfully but cannot exercise Keychain; use a normally signed Xcode run for session testing.

## Backend contract

`AppAuthBackend.swift` implements `DirectAuthBackend`. All paths are relative to your configured backend URL. HTTPS is required, redirects are rejected, responses are limited to 64 KiB, and credential-bearing requests are not automatically retried. JSON uses camelCase.

| Method and path | Request | Response |
| --- | --- | --- |
| POST `auth/direct/begin` | `applicationID`, `provider`, `state`, `redirectURI`; Apple `nonce` or GitHub `codeChallenge` and `codeChallengeMethod: "S256"` | `{ "transactionID": "single-use-id" }` |
| POST `auth/direct/exchange` | `applicationID`, `provider`, `transactionID`, `authorizationCode`; Apple `identityToken` or GitHub `codeVerifier` | Application session |
| GET `auth/me` | Bearer application access token | `subject`, optional `name`, `email`, `picture`, `githubLogin`, `githubID` |
| POST `auth/session/refresh` | `applicationID`, `refreshToken` | Session with a replacement refresh token and the same internal identity |
| POST `auth/session/revoke` | Bearer application access token and `{}` | HTTP 200–299 after revoking the session |

```json
{
  "subject": "internal-user-id",
  "accessToken": "application-access-token",
  "expiresAt": 1790900000,
  "refreshToken": "rotated-application-refresh-token"
}
```

`expiresAt` is Unix time in seconds and must be in the future. A refresh token is optional at initial login but required to restore a session after restart. Refresh must return a nonempty replacement token. HTTP 401 during refresh means the token is definitively invalid; uncertain outcomes require a new login. Provider tokens must never be used as application tokens, and email must never be used as the internal subject.

Implement the server verification and lifecycle requirements in [Provider setup](../../Docs/ProviderSetup.md#direct-sign-in-with-your-own-backend) before enabling real login. The [optional GitHub test backend](TestBackend/README.md) demonstrates this wire format without persistent storage. It is not a production backend.

## Verification

Build without device signing requirements:

```sh
xcodebuild -project Examples/ExampleAuthApp/ExampleAuthApp.xcodeproj \
  -scheme ExampleAuthApp -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Run the app's model and transport tests through the `ExampleAuthApp` scheme in Xcode. Run the backend tests with `npm test` from `TestBackend`. Package CI also builds the example and runs the backend tests. Real provider flows, signed Keychain behavior, session restoration, refresh rotation, account switching, logout, and physical-device behavior must be verified for your own app and backend before production use.
