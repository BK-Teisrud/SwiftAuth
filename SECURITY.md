# Security policy

Do not include tokens, authorization codes, PKCE material, private keys, one-time codes, callback URLs, personal data, or details of an unpatched vulnerability in public issues, pull requests, or test logs.

Report vulnerabilities through GitHub Private Vulnerability Reporting under the repository's Security tab. If that channel is unavailable, contact the repository owner privately before publishing details.

Include the affected version or commit, platform, expected and actual behavior, a minimal reproduction using synthetic data, and the potential impact. For direct login, backend transaction verification, provider secrets, user mappings and application session issuance are responsibilities of the integrating backend. Never publish provider evidence or transaction identifiers. See the [security contracts](Sources/Auth/Auth.docc/Security.md) for the package's boundaries.

Security fixes are prioritized for the latest published 0.x version. No long-term support guarantee is provided for older 0.x versions. A green package build does not verify a provider, broker, backend, signing, entitlement, or physical-device integration.
