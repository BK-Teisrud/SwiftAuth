# Auth documentation

The canonical guide is the [Auth DocC catalog](../Sources/Auth/Auth.docc/Auth.md). Public Swift declarations also include Quick Help documentation.

| Guide | Contents |
| --- | --- |
| [Getting started](../Sources/Auth/Auth.docc/GettingStarted.md) | Installation, application startup, login, and the first API request |
| [Configuration](../Sources/Auth/Auth.docc/Configuration.md) | Defaults, scopes, resources, callbacks, trusted origins, and namespaces |
| [Session lifecycle](../Sources/Auth/Auth.docc/SessionLifecycle.md) | Restore, login, refresh, cancellation, account changes, and logout |
| [Networking integration](../Sources/Auth/Auth.docc/NetworkingIntegration.md) | Credential binding and protected requests |
| [Providers and extensions](../Sources/Auth/Auth.docc/ProvidersAndExtensions.md) | Direct Apple/GitHub, backend sessions, hosted OIDC, and extension contracts |
| [Errors and recovery](../Sources/Auth/Auth.docc/ErrorsAndRecovery.md) | `AuthError`, recovery actions, and Networking error mapping |
| [Security](../Sources/Auth/Auth.docc/Security.md) | Direct backend trust, PKCE, JWS/JWK, claims, limits, Keychain, and logout markers |
| [Architecture](../Sources/Auth/Auth.docc/Architecture.md) | Ownership, actors, persistence, and maintenance boundaries |
| [Public API reference](../Sources/Auth/Auth.docc/APIReference.md) | Public types, properties, initializers, methods, and defaults |
| [Testing and release](../Sources/Auth/Auth.docc/TestingAndRelease.md) | Test suites, signed integration checks, DocC, CI, and release gates |

[Provider setup](ProviderSetup.md) describes the direct backend contract and hosted service/application integration checklists.

The [example iOS application](../Examples/ExampleAuthApp/README.md) demonstrates direct sign-in with this checkout and includes an optional GitHub test backend.

Read the Markdown directly on GitHub or build the DocC catalog in Xcode. Do not commit generated DocC archives, symbol graphs, DerivedData, test results, analysis reports, or internal findings.

## Documentation policy

All public documentation, Swift documentation comments, issue templates, and pull-request templates must be written in English. Examples must use synthetic hosts, identifiers, and credentials. Documentation must distinguish package verification from unverified provider, backend, entitlement, and physical-device integration.

The published Markdown set is intentionally limited to:

- `README.md` and `SECURITY.md` at the repository root;
- this index and `ProviderSetup.md` under `Docs`;
- the canonical articles in `Sources/Auth/Auth.docc`;
- GitHub issue and pull-request templates;
- the example app and test backend READMEs under `Examples/ExampleAuthApp`.

Do not add standalone changelogs, roadmaps, contribution guides, release checklists, repository-setup notes, agent instructions, audit reports, migration reports, meeting notes, or duplicate handbooks. Put durable product guidance in the closest existing article, keep release evidence outside the repository, and use Git history and GitHub Releases for change history.
