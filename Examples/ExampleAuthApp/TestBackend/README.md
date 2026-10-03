# GitHub test backend

A dependency-free Node.js backend for the SwiftAuth example. It uses real GitHub OAuth with S256 PKCE and keeps users and application sessions in memory. Restarting the server invalidates sessions and resets test user IDs. Apple, persistent storage, account linking, recovery, and production operations are not implemented.

## Start

Requires Node.js 22 or later. No npm installation is needed.

1. Copy `.env.example` to `.env`.
2. Set `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, and `GITHUB_ALLOWED_LOGIN`. Create your own GitHub OAuth app; credentials are not included.
3. Register `exampleauthapp://auth/callback` in that OAuth app. Keep wildcard callbacks and Device Flow disabled.
4. Run `npm start` from this directory. The server listens on `127.0.0.1:8787`.
5. Install Cloudflare's `cloudflared` separately and run `cloudflared tunnel --url http://127.0.0.1:8787 --no-autoupdate --protocol http2`, or provide an equivalent HTTPS tunnel.
6. Enter the tunnel's HTTPS URL, the configured application ID, and public GitHub client ID in the example app. If the tunnel URL changes, update the app settings and sign in again.

`.env`, local binaries under `bin`, and runtime files under `.runtime` are ignored by Git. Never publish secrets, tokens, or callback URLs containing authorization codes. Only the allowlisted GitHub account can sign in through the public test tunnel.

`GET /health` reports `githubReady`. The server does not issue fake sessions when credentials are missing. Apple requests return HTTP 501.

## API and limits

- `POST /auth/direct/begin`: expiring, single-use transaction bound to the application, callback, state, and PKCE challenge.
- `POST /auth/direct/exchange`: verifies PKCE and consumes the transaction before server-side code exchange. Fetches the authenticated GitHub user and enforces `GITHUB_ALLOWED_LOGIN`.
- `GET /auth/me`: returns the internal user profile for an application access token.
- `POST /auth/session/refresh`: rotates application refresh tokens atomically; reusing a consumed token revokes its session.
- `POST /auth/session/revoke`: revokes application access and refresh tokens.

Access tokens last 10 minutes, refresh tokens 24 hours, and login transactions 5 minutes. Application tokens are opaque random values; only SHA-256 fingerprints are stored. GitHub tokens are neither returned as app tokens nor stored in application sessions. Upstream redirects are rejected, responses are bounded, and raw secrets and upstream error payloads are not logged. The global limit is 120 API requests per minute.

## Tests

Run `npm test`. Tests use synthetic upstream responses and cover sessions, internal identity, rotation, replay rejection, revocation, expired transactions, PKCE, application/callback allowlists, account restrictions, redacted errors, and concurrent exchanges. They perform no real GitHub sign-in.

Provider verification and this API format can be adapted to an existing backend later. See the package's [backend integration requirements](../../../Docs/ProviderSetup.md#direct-sign-in-with-your-own-backend).

[GitHub OAuth documentation](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps) · [Cloudflare Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)
