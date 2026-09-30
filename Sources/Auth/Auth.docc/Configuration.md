# Configuration

Treat ``AuthConfiguration`` as an immutable trust contract for one public OIDC client, one API resource, and one local storage identity.

## Required values

- `issuer` is the exact HTTPS issuer URL. User information, query, and fragments are rejected.
- `clientID` identifies a public native client. Never ship a client secret.
- `redirectURI` must exactly match provider and application registration.
- `keychainNamespace` must uniquely identify the application and environment.

`scopes` defaults to `openid` and `offline_access`, must include `openid`, and cannot contain duplicates or whitespace-delimited values.

## API resource

Use `.auth0Audience` only when the service explicitly defines the `audience` parameter. Use `.oauthResource` for RFC 8707 `resource`. The value identifies the protected API and is not inferred from the issuer or the Networking base URL.

The resource participates in the storage and process-lock identity. Multi-resource token exchange is not supported by this version.

## Login choices

``AuthLoginChoice/serviceSelection`` lets the hosted service present its configured choices. ``AuthLoginChoice/connection(_:)`` sends an exact provider-specific connection name. It does not install Apple, Vipps, email, or SMS support by itself. Enable a connection only after its broker integration has been configured and tested.

## Redirects and logout

`postLogoutRedirectURI` enables separate provider logout when discovery publishes `end_session_endpoint`. Run provider logout before local logout when the service requires an in-memory ID-token hint. Auth never persists ID tokens.

`prefersEphemeralWebBrowserSession` requests an ephemeral browser session but does not guarantee provider logout or isolation from all system browser state.

## Endpoint trust

Discovery endpoints on the issuer origin are trusted by default. Add only reviewed HTTPS origins to `trustedEndpointOrigins`. URLs with credentials or fragments are rejected. Static endpoint query parameters are preserved unless they collide with protocol parameters supplied by Auth.

`trustedIDTokenAudiences` adds reviewed ID-token audiences, not API resources. The client ID remains required, and the audience set is bound to the session across refresh and restart.

## Refresh timeout

`refreshTimeout` defaults to 60 seconds and must be greater than zero and no more than 3600 seconds. It covers refresh preparation, token exchange, validation, and persistence. It does not limit the time a user spends in the browser.

## Storage

The namespace, issuer, client ID, and API resource are encoded and hashed to derive storage identifiers. Use separate namespaces for development, staging, and production. Keychain access groups and application-extension sharing are not supported.
