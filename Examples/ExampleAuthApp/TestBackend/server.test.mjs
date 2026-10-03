import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createBackend } from './server.mjs';
const config = { clientID: 'public-id', clientSecret: 'synthetic-test-secret', allowedLogin: 'octocat',
  applicationID: 'no.teisrud.ExampleAuthApp', redirectURI: 'exampleauthapp://auth/callback' };
const verifier = 'v'.repeat(43);
const challenge = createHash('sha256').update(verifier).digest('base64url');
async function fixture(t, overrides = {}, fetchImpl) {
  let time = Date.now();
  let calls = 0;
  const server = createBackend({ ...config, ...overrides }, {
    now: () => time,
    fetchImpl: fetchImpl || (async (url, options) => {
      calls++;
      assert.equal(options.redirect, 'error');
      if (url.includes('access_token')) {
        assert.equal(options.body.get('code_verifier'), verifier);
        return Response.json({ access_token: 'synthetic-provider-token', token_type: 'bearer' });
      }
      assert.equal(options.headers.Authorization, 'Bearer synthetic-provider-token');
      return Response.json({ id: 12345, login: 'octocat', name: 'Synthetic User' });
    })
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const url = `http://127.0.0.1:${server.address().port}`;
  async function request(path, body, token) {
    const response = await fetch(url + path, { method: body === undefined ? 'GET' : 'POST',
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body) });
    return { status: response.status, body: await response.json() };
  }
  const begin = () => request('/auth/direct/begin', { applicationID: config.applicationID, provider: 'github',
    state: 's'.repeat(43), redirectURI: config.redirectURI, codeChallenge: challenge, codeChallengeMethod: 'S256' });
  const exchange = id => request('/auth/direct/exchange', { applicationID: config.applicationID,
    provider: 'github', transactionID: id, authorizationCode: 'synthetic-code', codeVerifier: verifier });
  return { request, begin, exchange, advance: ms => { time += ms; }, calls: () => calls };
}

test('real provider exchange creates app credentials and stable internal identity', async t => {
  const f = await fixture(t);
  const first = await f.begin();
  const login = await f.exchange(first.body.transactionID);
  assert.equal(login.status, 200);
  assert.notEqual(login.body.accessToken, 'synthetic-provider-token');
  assert.notEqual(login.body.subject, '12345');
  const profile = await f.request('/auth/me', undefined, login.body.accessToken);
  assert.equal(profile.body.subject, login.body.subject);
  assert.equal(profile.body.githubID, '12345');
  const second = await f.exchange((await f.begin()).body.transactionID);
  assert.equal(second.body.subject, login.body.subject);
  assert.equal((await f.exchange(first.body.transactionID)).status, 401);
});
test('refresh rotates, rejects replay and revokes the compromised family', async t => {
  const f = await fixture(t);
  const login = (await f.exchange((await f.begin()).body.transactionID)).body;
  const refresh = token => f.request('/auth/session/refresh', { applicationID: config.applicationID, refreshToken: token });
  const rotated = await refresh(login.refreshToken);
  assert.equal(rotated.status, 200);
  assert.notEqual(rotated.body.refreshToken, login.refreshToken);
  assert.equal(rotated.body.subject, login.subject);
  assert.equal((await f.request('/auth/me', undefined, login.accessToken)).status, 401);
  assert.equal((await refresh(login.refreshToken)).status, 401);
  assert.equal((await f.request('/auth/me', undefined, rotated.body.accessToken)).status, 401);
});
test('logout revokes access and refresh', async t => {
  const f = await fixture(t);
  const login = (await f.exchange((await f.begin()).body.transactionID)).body;
  assert.equal((await f.request('/auth/session/revoke', {}, login.accessToken)).status, 200);
  assert.equal((await f.request('/auth/me', undefined, login.accessToken)).status, 401);
  assert.equal((await f.request('/auth/session/refresh', { applicationID: config.applicationID, refreshToken: login.refreshToken })).status, 401);
});
test('expired transactions never contact GitHub', async t => {
  const f = await fixture(t);
  const begin = await f.begin();
  f.advance(301_000);
  assert.equal((await f.exchange(begin.body.transactionID)).status, 401);
  assert.equal(f.calls(), 0);
});
test('wrong verifier is consumed and never contacts GitHub', async t => {
  const f = await fixture(t);
  const id = (await f.begin()).body.transactionID;
  const response = await f.request('/auth/direct/exchange', { applicationID: config.applicationID,
    provider: 'github', transactionID: id, authorizationCode: 'code', codeVerifier: 'x'.repeat(43) });
  assert.equal(response.status, 401);
  assert.equal((await f.exchange(id)).status, 401);
  assert.equal(f.calls(), 0);
});
test('only configured application, callback and provider are accepted', async t => {
  const f = await fixture(t);
  for (const change of [{ applicationID: 'attacker' }, { redirectURI: 'other://callback' }, { codeChallengeMethod: 'plain' }]) {
    assert.equal((await f.request('/auth/direct/begin', { applicationID: config.applicationID, provider: 'github',
      state: 's'.repeat(43), redirectURI: config.redirectURI, codeChallenge: challenge, codeChallengeMethod: 'S256', ...change })).status, 400);
  }
  assert.equal((await f.request('/auth/direct/begin', { applicationID: config.applicationID, provider: 'apple' })).status, 501);
});
test('unconfigured server exposes readiness but never accepts dummy login', async t => {
  const f = await fixture(t, { clientSecret: '' });
  const health = await f.request('/health');
  assert.equal(health.body.githubReady, false);
  assert.equal(JSON.stringify(health.body).includes('synthetic-test-secret'), false);
  assert.equal((await f.begin()).status, 503);
});
test('non-allowlisted account cannot get session', async t => {
  const f = await fixture(t, { allowedLogin: 'someone-else' });
  assert.equal((await f.exchange((await f.begin()).body.transactionID)).status, 403);
});
test('provider failures return no secrets or raw body', async t => {
  const f = await fixture(t, {}, async () => { throw new Error('synthetic-sensitive-content'); });
  const response = await f.exchange((await f.begin()).body.transactionID);
  assert.equal(response.status, 502);
  assert.deepEqual(response.body, { error: 'request_failed' });
});
test('concurrent exchanges issue exactly one session', async t => {
  const f = await fixture(t);
  const id = (await f.begin()).body.transactionID;
  const results = await Promise.all([f.exchange(id), f.exchange(id)]);
  assert.deepEqual(results.map(x => x.status).sort(), [200, 401]);
});
