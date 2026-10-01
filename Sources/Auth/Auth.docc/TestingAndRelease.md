# Testing and release

Package verification proves deterministic library contracts. Provider, entitlement, Keychain, and backend behavior require separate tests in the integrating application.

## Package checks

```sh
swift build
swift test
xcrun swift-format lint --strict --recursive Package.swift Sources Tests
```

The test suite covers session transitions, concurrent refresh, cancellation, persistence ordering, logout recovery, account switching, Networking integration, callback validation, discovery trust, response limits, duplicate JSON keys, synthetic RSA signatures, JWK selection, and OIDC claims. Direct adapter tests also cover GitHub S256 PKCE, backend-issued application credentials, invalid/duplicate callbacks, cancellation, unsupported selection, Apple cancellation and refresh identity preservation. Tests do not contact a public provider or implement the production backend.

The Keychain integration case in the SwiftPM suite is disabled unless a signed application test host defines `AUTH_HOSTED_KEYCHAIN_TESTS`. This repository intentionally ships no application project. The consuming application must own and run that signed test on supported iOS and macOS versions.

## DocC

Open the package in Xcode and use Build Documentation for the Auth scheme. CI builds DocC with warnings treated as errors. Do not commit `.doccarchive`, symbol graphs, DerivedData, or test result bundles.

## Continuous integration

CI builds production code with the minimum Swift 6 toolchain, runs the full suite with the current toolchain, checks formatting, builds DocC, and builds and tests the package on an iOS simulator. Xcode 16.0 cannot compile this suite's early Swift Testing MainActor throwing closures, so the minimum-toolchain job is a production-build gate rather than a full test gate.

A green workflow does not claim signed Data Protection Keychain behavior, callback entitlements, provider configuration, physical-device behavior, or backend authorization.

## Application release gates

Before an application release, verify:

1. exact provider/client/callback configuration; for direct login, server transactions, Apple verification, GitHub PKCE exchange, internal user mapping and application-token issuance; for hosted OIDC, scopes, connections, audience/resource and JWKS;
2. every enabled login method on simulator and physical device;
3. signed Data Protection Keychain behavior, locked-device handling, failed deletion, and pending logout recovery;
4. refresh success, atomic rotation, definitive rejection, timeout after possible send, termination, restart quarantine, transaction replay rejection and server session revocation;
5. account changes, delayed 401 responses, late results, and cache isolation;
6. the real access token against the protected backend, including insufficient scope and revoked access;
7. sanitized evidence recording Auth and Networking versions, OS versions, environment, and limitations.

No live provider or backend integration is currently recorded as verified by this package. Never store tokens, one-time codes, private keys, or personal data in release evidence.
