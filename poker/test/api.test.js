'use strict';
const test = require('node:test');
const assert = require('node:assert');
const http = require('http');
const { createStore } = require('../lib/store');
const { createApi } = require('../lib/api');

async function startServer() {
  const api = createApi(createStore(null));
  const server = http.createServer(api.handle);
  await new Promise((r) => server.listen(0, r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, url, body, token) => {
    const res = await fetch(base + url, {
      method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: res.status, body: await res.json() };
  };
  return { server, call };
}

test('a whole poker night, with host-only powers enforced', async (t) => {
  const { server, call } = await startServer();
  t.after(() => server.close());

  const host = (await call('POST', '/api/signup', { name: 'Dana', pin: '1234' })).body;
  const avi = (await call('POST', '/api/signup', { name: 'Avi', pin: '4321' })).body;
  const ben = (await call('POST', '/api/signup', { name: 'Ben', pin: '1111' })).body;
  const outsider = (await call('POST', '/api/signup', { name: 'Zed', pin: '9999' })).body;
  assert.equal((await call('POST', '/api/signup', { name: 'dana', pin: '5555' })).status, 409);
  assert.equal((await call('POST', '/api/login', { name: 'DANA', pin: '0000' })).status, 401);
  assert.ok((await call('POST', '/api/login', { name: 'DANA', pin: '1234' })).body.token);

  let g = (await call('POST', '/api/games', { name: 'Friday', currency: 'ILS', chipValue: 5, buyIns: [100, 50] }, host.token)).body;
  assert.deepEqual(g.buyIns, [50, 100]);
  assert.equal(g.isAdmin, true);

  // Invite preview is public; joining needs a login.
  assert.equal((await call('GET', `/api/invite/${g.code}`)).body.host, 'Dana');
  assert.equal((await call('POST', `/api/invite/${g.code}/join`)).status, 401);
  await call('POST', `/api/invite/${g.code}/join`, {}, avi.token);
  await call('POST', `/api/invite/${g.code}/join`, {}, ben.token);

  // Outsiders can't see or add to the table.
  assert.equal((await call('GET', `/api/games/${g.id}`, null, outsider.token)).status, 403);
  assert.equal((await call('POST', `/api/games/${g.id}/entries`, { amount: 100 }, outsider.token)).status, 403);

  // Players request; only listed options are allowed.
  assert.equal((await call('POST', `/api/games/${g.id}/entries`, { amount: 77 }, avi.token)).status, 400);
  g = (await call('POST', `/api/games/${g.id}/entries`, { amount: 100 }, avi.token)).body;
  const aviEntry = g.entries.find((e) => e.userId === avi.user.id);
  assert.equal(aviEntry.status, 'pending');
  assert.equal(g.totals.pot, 0);

  // Players can't approve, edit, or add for others.
  assert.equal((await call('POST', `/api/games/${g.id}/entries/${aviEntry.id}/approve`, {}, avi.token)).status, 403);
  assert.equal((await call('PATCH', `/api/games/${g.id}/entries/${aviEntry.id}`, { amount: 500 }, avi.token)).status, 403);
  assert.equal((await call('POST', `/api/games/${g.id}/entries`, { amount: 100, userId: ben.user.id }, avi.token)).status, 403);

  g = (await call('POST', `/api/games/${g.id}/entries/${aviEntry.id}/approve`, {}, host.token)).body;
  assert.equal(g.totals.pot, 100);

  // Once approved, only the host can delete it.
  assert.equal((await call('DELETE', `/api/games/${g.id}/entries/${aviEntry.id}`, null, avi.token)).status, 403);

  // Ben requests twice, withdraws one, the other is approved.
  g = (await call('POST', `/api/games/${g.id}/entries`, { amount: 50 }, ben.token)).body;
  g = (await call('POST', `/api/games/${g.id}/entries`, { amount: 50 }, ben.token)).body;
  const [b1, b2] = g.entries.filter((e) => e.userId === ben.user.id);
  g = (await call('DELETE', `/api/games/${g.id}/entries/${b1.id}`, null, ben.token)).body;
  g = (await call('POST', `/api/games/${g.id}/entries/approve-all`, {}, host.token)).body;
  assert.equal(g.entries.find((e) => e.id === b2.id).status, 'approved');

  // Host adds for themself (auto-approved) and edits Avi's entry.
  g = (await call('POST', `/api/games/${g.id}/entries`, { amount: 100 }, host.token)).body;
  g = (await call('PATCH', `/api/games/${g.id}/entries/${aviEntry.id}`, { amount: 150 }, host.token)).body;
  assert.equal(g.totals.pot, 300);
  assert.equal(g.totals.potChips, 60);

  // Cash-outs: players set their own; the host can set anyone's.
  assert.equal((await call('PUT', `/api/games/${g.id}/cashouts/${ben.user.id}`, { chips: 5 }, avi.token)).status, 403);
  await call('PUT', `/api/games/${g.id}/cashouts/${avi.user.id}`, { chips: 40 }, avi.token); // 200
  await call('PUT', `/api/games/${g.id}/cashouts/${ben.user.id}`, { chips: 0 }, host.token); // 0
  g = (await call('PUT', `/api/games/${g.id}/cashouts/${host.user.id}`, { chips: 19 }, host.token)).body; // 95 (5 short)

  // Players can't end it; unbalanced needs force.
  assert.equal((await call('POST', `/api/games/${g.id}/end`, {}, avi.token)).status, 403);
  const unb = await call('POST', `/api/games/${g.id}/end`, {}, host.token);
  assert.equal(unb.status, 409);
  assert.equal(unb.body.code, 'unbalanced');
  await call('PUT', `/api/games/${g.id}/cashouts/${host.user.id}`, { chips: 20 }, host.token);
  g = (await call('POST', `/api/games/${g.id}/end`, {}, host.token)).body;
  assert.equal(g.status, 'ended');

  const net = Object.fromEntries(g.lines.map((l) => [l.userId, l.net]));
  assert.deepEqual(net, { [host.user.id]: 0, [avi.user.id]: 50, [ben.user.id]: -50 });
  assert.deepEqual(g.settlements, [{ from: ben.user.id, to: avi.user.id, amount: 50, paid: false }]);

  // Locked after the end; host can reopen.
  assert.equal((await call('POST', `/api/games/${g.id}/entries`, { amount: 50 }, host.token)).status, 409);

  // Only people involved can mark a payment.
  g = (await call('POST', `/api/games/${g.id}/settlements/0`, { paid: true }, ben.token)).body;
  assert.equal(g.settlements[0].paid, true);

  const stats = (await call('GET', '/api/stats', null, avi.token)).body;
  const aviStats = stats.players.find((p) => p.user.id === avi.user.id).byCurrency.ILS;
  assert.equal(aviStats.net, 50);
  assert.equal(aviStats.games, 1);
  assert.equal(stats.players.some((p) => p.user.id === outsider.user.id), false);

  // Host can remove a player only while live.
  assert.equal((await call('DELETE', `/api/games/${g.id}/players/${ben.user.id}`, null, host.token)).status, 409);
  await call('POST', `/api/games/${g.id}/reopen`, {}, host.token);
  assert.equal((await call('DELETE', `/api/games/${g.id}/players/${ben.user.id}`, null, avi.token)).status, 403);
  g = (await call('DELETE', `/api/games/${g.id}/players/${ben.user.id}`, null, host.token)).body;
  assert.equal(g.players.length, 2);
});

test('login is locked after repeated wrong PINs', async (t) => {
  const { server, call } = await startServer();
  t.after(() => server.close());
  await call('POST', '/api/signup', { name: 'Lee', pin: '2468' });
  for (let i = 0; i < 8; i++) assert.equal((await call('POST', '/api/login', { name: 'Lee', pin: '0000' })).status, 401);
  assert.equal((await call('POST', '/api/login', { name: 'Lee', pin: '2468' })).status, 429);
});
