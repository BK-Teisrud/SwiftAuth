import http from 'node:http';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const random = () => randomBytes(32).toString('base64url');
const hash = value => createHash('sha256').update(value).digest('base64url');
class Failure extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
const fail = (status, code) => { throw new Failure(status, code); };
const validString = (value, max = 4096) => typeof value === 'string' && value.length > 0 && value.length <= max;

// Ephemeral GitHub-only test service. Restarting drops all transactions and sessions.
export function createBackend(config, { fetchImpl = fetch, now = () => Date.now() } = {}) {
  const transactions = new Map(), accesses = new Map(), refreshes = new Map();
  const spentRefreshes = new Map(), users = new Map(), sessions = new Set();
  const ready = Boolean(config.clientID && config.clientSecret && config.allowedLogin);
  let rateStart = now(), requestCount = 0;
  function cleanup() {
    const time = now();
    for (const [key, value] of transactions) if (value.expires <= time) transactions.delete(key);
    for (const [key, value] of spentRefreshes) if (value.expires <= time) spentRefreshes.delete(key);
    for (const session of sessions) if (session.refreshExpires <= time) revoke(session);
  }
  function revoke(session) {
    accesses.delete(session.accessHash);
    refreshes.delete(session.refreshHash);
    sessions.delete(session);
  }
  function issue(session) {
    const accessToken = random(), refreshToken = random();
    accesses.delete(session.accessHash);
    refreshes.delete(session.refreshHash);
    session.accessHash = hash(accessToken);
    session.refreshHash = hash(refreshToken);
    session.accessExpires = now() + 10 * 60_000;
    session.refreshExpires = now() + 24 * 60 * 60_000;
    accesses.set(session.accessHash, session);
    refreshes.set(session.refreshHash, session);
    sessions.add(session);
    return { subject: session.user.subject, accessToken,
      expiresAt: session.accessExpires / 1000, refreshToken };
  }
  function authenticated(req) {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ') || !validString(header.slice(7))) fail(401, 'unauthorized');
    const session = accesses.get(hash(header.slice(7)));
    if (!session || session.accessExpires <= now()) fail(401, 'unauthorized');
    return session;
  }
  function app(body) {
    if (body.applicationID !== config.applicationID) fail(400, 'invalid_application');
  }
  async function githubJSON(url, options) {
    const response = await fetchImpl(url, { ...options, redirect: 'error', signal: AbortSignal.timeout(15_000) });
    if (!response.ok) fail(401, 'provider_rejected');
    const reader = response.body.getReader();
    const chunks = [];
    let size = 0;
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > 65_536) fail(502, 'provider_response_invalid');
        chunks.push(Buffer.from(value));
      }
    } finally { await reader.cancel(); }
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  }
  const server = http.createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Content-Type', 'application/json');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    const send = (status, body) => { res.writeHead(status); res.end(JSON.stringify(body)); };
    try {
      const path = new URL(req.url, 'http://localhost').pathname;
      if (req.method === 'GET' && path === '/health') {
        return send(200, { status: 'ok', githubReady: ready, applicationID: config.applicationID,
          githubClientID: config.clientID || null, redirectURI: config.redirectURI });
      }
      cleanup();
      if (now() - rateStart >= 60_000) { rateStart = now(); requestCount = 0; }
      if (++requestCount > 120) fail(429, 'rate_limited');
      if (req.method === 'GET' && path === '/auth/me') return send(200, authenticated(req).user);
      if (req.method !== 'POST') fail(404, 'not_found');
      if (req.headers['content-type']?.split(';')[0] !== 'application/json') fail(415, 'json_required');
      let size = 0;
      const chunks = [];
      for await (const chunk of req) {
        size += chunk.length;
        if (size > 16_384) fail(413, 'request_too_large');
        chunks.push(chunk);
      }
      let body;
      try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
      catch { fail(400, 'invalid_json'); }
      if (!body || typeof body !== 'object' || Array.isArray(body)) fail(400, 'invalid_json');
      if (path === '/auth/session/revoke') {
        revoke(authenticated(req));
        return send(200, { revoked: true });
      }
      app(body);
      if (path === '/auth/direct/begin') {
        if (body.provider !== 'github') fail(501, 'github_only_test_backend');
        if (!ready) fail(503, 'github_setup_required');
        if (body.redirectURI !== config.redirectURI || !validString(body.state, 256)
          || body.state.length < 32 || body.codeChallengeMethod !== 'S256'
          || !/^[A-Za-z0-9_-]{43}$/.test(body.codeChallenge || '')) fail(400, 'invalid_transaction');
        if (transactions.size >= 500) fail(429, 'rate_limited');
        const transactionID = random();
        transactions.set(transactionID, { state: body.state, challenge: body.codeChallenge,
          expires: now() + 5 * 60_000 });
        return send(200, { transactionID });
      }
      if (path === '/auth/direct/exchange') {
        if (body.provider !== 'github') fail(501, 'github_only_test_backend');
        if (!ready) fail(503, 'github_setup_required');
        const transaction = transactions.get(body.transactionID);
        if (!transaction) fail(401, 'transaction_invalid');
        // Consume before await: concurrent requests or unknown exchange results cannot reuse a code.
        transactions.delete(body.transactionID);
        if (!validString(body.authorizationCode) || !/^[A-Za-z0-9._~-]{43,128}$/.test(body.codeVerifier || '')
          || hash(body.codeVerifier) !== transaction.challenge) fail(401, 'transaction_invalid');
        const token = await githubJSON('https://github.com/login/oauth/access_token', {
          method: 'POST', headers: { Accept: 'application/json', 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({ client_id: config.clientID, client_secret: config.clientSecret,
            code: body.authorizationCode, redirect_uri: config.redirectURI, code_verifier: body.codeVerifier })
        });
        if (!validString(token.access_token) || token.error || token.token_type?.toLowerCase() !== 'bearer') fail(401, 'provider_rejected');
        const profile = await githubJSON('https://api.github.com/user', {
          headers: { Authorization: `Bearer ${token.access_token}`, Accept: 'application/vnd.github+json',
            'User-Agent': 'ExampleAuthApp-TestBackend', 'X-GitHub-Api-Version': '2022-11-28' }
        });
        if (!Number.isSafeInteger(profile.id) || profile.id <= 0 || !validString(profile.login, 100)) fail(401, 'provider_rejected');
        if (profile.login.toLowerCase() !== config.allowedLogin.toLowerCase()) fail(403, 'account_not_allowed');
        const providerID = String(profile.id);
        const user = { subject: users.get(providerID)?.subject || randomUUID(),
          name: typeof profile.name === 'string' ? profile.name : null,
          githubLogin: profile.login, githubID: providerID };
        users.set(providerID, user);
        // GitHub credentials are never stored as session credentials or returned to the app.
        return send(200, issue({ user }));
      }
      if (path === '/auth/session/refresh') {
        if (!validString(body.refreshToken)) fail(401, 'refresh_rejected');
        const fingerprint = hash(body.refreshToken);
        const spent = spentRefreshes.get(fingerprint);
        if (spent) { revoke(spent.session); fail(401, 'refresh_rejected'); }
        const session = refreshes.get(fingerprint);
        if (!session || session.refreshExpires <= now()) fail(401, 'refresh_rejected');
        spentRefreshes.set(fingerprint, { session, expires: session.refreshExpires });
        return send(200, issue(session));
      }
      fail(404, 'not_found');
    } catch (error) {
      // Never log upstream bodies, URLs, authorization codes, tokens, or secrets.
      if (!res.headersSent) send(error instanceof Failure ? error.status : 502,
        { error: error instanceof Failure ? error.code : 'request_failed' });
      else res.end();
    }
  });
  server.requestTimeout = 30_000;
  server.headersTimeout = 10_000;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const config = {
    clientID: process.env.GITHUB_CLIENT_ID || '', clientSecret: process.env.GITHUB_CLIENT_SECRET || '',
    allowedLogin: process.env.GITHUB_ALLOWED_LOGIN || '',
    applicationID: process.env.APPLICATION_ID || 'no.teisrud.ExampleAuthApp',
    redirectURI: process.env.REDIRECT_URI || 'exampleauthapp://auth/callback'
  };
  const port = Number(process.env.PORT || 8787);
  const server = createBackend(config);
  server.listen(port, '127.0.0.1', () => {
    console.log(`Test backend: http://127.0.0.1:${port}`);
    console.log(config.clientID && config.clientSecret && config.allowedLogin
      ? 'GitHub login configured.' : 'Set GitHub credentials and allowed login in .env, then restart.');
  });
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(() => process.exit(0)));
}
