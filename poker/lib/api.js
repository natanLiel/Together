'use strict';
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { round2, playerLines, gameTotals, settle, statsFor, badges } = require('./logic');

const CURRENCIES = ['ILS', 'USD', 'EUR', 'GBP'];
const COLORS = ['#e4572e', '#29335c', '#f3a712', '#669bbc', '#a8c686', '#8e5572', '#2a9d8f', '#e76f51', '#6a4c93', '#1982c4'];
const PUBLIC_DIR = path.join(__dirname, '..', 'public');
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json', '.webmanifest': 'application/manifest+json', '.svg': 'image/svg+xml', '.png': 'image/png',
};

class HttpError extends Error {
  constructor(status, message, extra) { super(message); this.status = status; this.extra = extra; }
}
const fail = (status, message, extra) => { throw new HttpError(status, message, extra); };

const id = (bytes = 9) => crypto.randomBytes(bytes).toString('base64url');
const inviteCode = () => {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let s = '';
  for (const b of crypto.randomBytes(6)) s += alphabet[b % alphabet.length];
  return s;
};
const hashPin = (pin, salt) => crypto.scryptSync(String(pin), salt, 32).toString('hex');
const normName = (n) => String(n || '').trim().replace(/\s+/g, ' ');
const nameKey = (n) => normName(n).toLowerCase();
const today = () => new Date().toISOString().slice(0, 10);

function checkPin(pin) {
  if (!/^\d{4,6}$/.test(String(pin || ''))) fail(400, 'PIN must be 4–6 digits');
}
function checkName(name) {
  const n = normName(name);
  if (n.length < 2 || n.length > 24) fail(400, 'Name must be 2–24 characters');
  return n;
}
function money(v, label = 'Amount') {
  const n = Number(v);
  if (!Number.isFinite(n) || n <= 0 || n > 1e7) fail(400, `${label} must be a positive number`);
  return round2(n);
}
function chipCount(v) {
  const n = Number(v);
  if (!Number.isFinite(n) || n < 0 || n > 1e8) fail(400, 'Chips must be zero or more');
  return round2(n);
}
function buyInList(list) {
  if (!Array.isArray(list)) fail(400, 'Entry options are required');
  const clean = [...new Set(list.map((v) => money(v, 'Entry option')))].sort((a, b) => a - b);
  if (!clean.length || clean.length > 8) fail(400, 'Add between 1 and 8 entry options');
  return clean;
}

function createApi(store, opts = {}) {
  const db = store.data;
  const failures = new Map(); // nameKey -> { count, first }
  const now = opts.now || (() => Date.now());

  const userByName = (name) => Object.values(db.users).find((u) => u.key === nameKey(name));
  const publicUser = (u) => u && { id: u.id, name: u.name, color: u.color };

  function auth(req) {
    const h = req.headers.authorization || '';
    const token = h.startsWith('Bearer ') ? h.slice(7) : null;
    const s = token && db.sessions[token];
    const user = s && db.users[s.userId];
    if (!user) fail(401, 'Please log in');
    s.seenAt = now();
    return user;
  }

  function getGame(gameId, user) {
    const g = db.games[gameId];
    if (!g) fail(404, 'Game not found');
    if (user && !g.players.some((p) => p.userId === user.id)) fail(403, 'You are not at this table');
    return g;
  }
  const isAdmin = (g, user) => g.adminId === user.id;
  function requireAdmin(g, user) { if (!isAdmin(g, user)) fail(403, 'Only the host of the night can do that'); }
  function requireLive(g) { if (g.status !== 'live') fail(409, 'This night has ended. The host can reopen it to make changes.'); }
  function log(g, user, text) {
    g.log.unshift({ at: now(), by: user ? user.id : null, text });
    if (g.log.length > 300) g.log.length = 300;
    g.updatedAt = now();
  }
  const nameOf = (uid) => (db.users[uid] ? db.users[uid].name : 'Someone');
  const fmt = (g, n) => `${round2(n)} ${g.currency}`;

  function gameView(g, user) {
    const lines = playerLines(g);
    const users = {};
    for (const p of g.players) users[p.userId] = publicUser(db.users[p.userId]);
    for (const t of g.settlements || []) {
      users[t.from] = users[t.from] || publicUser(db.users[t.from]);
      users[t.to] = users[t.to] || publicUser(db.users[t.to]);
    }
    return {
      id: g.id, code: g.code, name: g.name, date: g.date, location: g.location, notes: g.notes,
      adminId: g.adminId, isAdmin: isAdmin(g, user), status: g.status,
      currency: g.currency, chipValue: g.chipValue, buyIns: g.buyIns, allowCustom: g.allowCustom,
      createdAt: g.createdAt, endedAt: g.endedAt, updatedAt: g.updatedAt,
      players: g.players, entries: g.entries, users, lines, totals: gameTotals(g),
      settlements: g.settlements || [], log: g.log.slice(0, 80),
    };
  }
  function gameCard(g, user) {
    const lines = playerLines(g);
    const mine = lines.find((l) => l.userId === user.id);
    const t = gameTotals(g);
    return {
      id: g.id, name: g.name, date: g.date, status: g.status, currency: g.currency, chipValue: g.chipValue,
      isAdmin: isAdmin(g, user), players: g.players.length, pot: t.pot, pendingEntries: t.pendingEntries,
      myBuyIn: mine ? mine.buyIn : 0, myNet: mine ? mine.net : null, updatedAt: g.updatedAt,
      adminName: nameOf(g.adminId),
    };
  }

  function coPlayerIds(user) {
    const ids = new Set([user.id]);
    for (const g of Object.values(db.games)) {
      if (g.players.some((p) => p.userId === user.id)) for (const p of g.players) ids.add(p.userId);
    }
    return ids;
  }

  function endGame(g, force) {
    const t = gameTotals(g);
    if (t.pendingEntries) fail(409, 'Approve or reject the pending entries first');
    if (t.missingCashouts.length) {
      fail(409, `Missing final chip counts for: ${t.missingCashouts.map(nameOf).join(', ')}`, { code: 'missing' });
    }
    if (!t.balanced && !force) {
      fail(409, `Chips don't add up: cash-outs are ${t.difference > 0 ? 'over' : 'under'} the pot by ${fmt(g, Math.abs(t.difference))}`, { code: 'unbalanced', difference: t.difference });
    }
    g.status = 'ended';
    g.endedAt = now();
    g.settlements = settle(playerLines(g).filter((l) => l.buyIn > 0).map((l) => ({ userId: l.userId, net: l.net })));
  }

  // ---- routes -------------------------------------------------------------
  const routes = [];
  const route = (method, pattern, handler) => {
    const keys = [];
    const re = new RegExp('^' + pattern.replace(/:(\w+)/g, (_, k) => { keys.push(k); return '([^/]+)'; }) + '$');
    routes.push({ method, re, keys, handler });
  };

  route('POST', '/api/signup', ({ body }) => {
    const name = checkName(body.name);
    checkPin(body.pin);
    if (userByName(name)) fail(409, 'That name is taken. Log in instead, or add a last initial.');
    const salt = id(12);
    const user = {
      id: id(), name, key: nameKey(name), salt, pinHash: hashPin(body.pin, salt),
      color: COLORS[Object.keys(db.users).length % COLORS.length], createdAt: now(),
    };
    db.users[user.id] = user;
    const token = id(24);
    db.sessions[token] = { userId: user.id, createdAt: now() };
    return { token, user: publicUser(user) };
  });

  route('POST', '/api/login', ({ body }) => {
    const key = nameKey(body.name);
    let f = failures.get(key);
    if (f && now() - f.first > 15 * 60e3) { failures.delete(key); f = null; }
    if (f && f.count >= 8) fail(429, 'Too many wrong PINs. Try again in a few minutes.');
    const user = userByName(body.name);
    if (!user || hashPin(body.pin, user.salt) !== user.pinHash) {
      failures.set(key, { count: (f ? f.count : 0) + 1, first: f ? f.first : now() });
      fail(401, 'Wrong name or PIN');
    }
    failures.delete(key);
    const token = id(24);
    db.sessions[token] = { userId: user.id, createdAt: now() };
    return { token, user: publicUser(user) };
  });

  route('POST', '/api/logout', ({ req }) => {
    const token = (req.headers.authorization || '').slice(7);
    delete db.sessions[token];
    return { ok: true };
  });

  route('GET', '/api/me', ({ user }) => {
    const games = Object.values(db.games)
      .filter((g) => g.players.some((p) => p.userId === user.id))
      .sort((a, b) => (a.status !== b.status ? (a.status === 'live' ? -1 : 1) : b.updatedAt - a.updatedAt))
      .map((g) => gameCard(g, user));
    const stats = statsFor(user.id, Object.values(db.games));
    const primary = stats.primary && stats.byCurrency[stats.primary];
    return { user: publicUser(user), games, stats, badges: badges(primary) };
  });

  route('PATCH', '/api/me', ({ user, body }) => {
    const name = body.name != null ? checkName(body.name) : null;
    if (name) {
      const other = userByName(name);
      if (other && other.id !== user.id) fail(409, 'That name is taken');
    }
    if (body.pin != null) {
      checkPin(body.pin);
      if (hashPin(body.currentPin, user.salt) !== user.pinHash) fail(403, 'Current PIN is wrong');
    }
    if (name) { user.name = name; user.key = nameKey(name); }
    if (body.pin != null) { user.salt = id(12); user.pinHash = hashPin(body.pin, user.salt); }
    if (body.color != null && COLORS.includes(body.color)) user.color = body.color;
    return { user: publicUser(user) };
  });

  route('POST', '/api/games', ({ user, body }) => {
    const currency = CURRENCIES.includes(body.currency) ? body.currency : fail(400, 'Pick a currency');
    const g = {
      id: id(), code: inviteCode(), adminId: user.id, status: 'live',
      name: normName(body.name).slice(0, 40) || `Poker night ${today()}`,
      date: /^\d{4}-\d{2}-\d{2}$/.test(body.date || '') ? body.date : today(),
      location: normName(body.location).slice(0, 60),
      notes: String(body.notes || '').slice(0, 300),
      currency, chipValue: money(body.chipValue, 'Chip value'), buyIns: buyInList(body.buyIns),
      allowCustom: !!body.allowCustom,
      players: [{ userId: user.id, joinedAt: now() }],
      entries: [], cashouts: {}, settlements: [], log: [],
      createdAt: now(), updatedAt: now(), endedAt: null,
    };
    db.games[g.id] = g;
    log(g, user, `${user.name} opened the table`);
    return gameView(g, user);
  });

  route('GET', '/api/games/:id', ({ user, params }) => gameView(getGame(params.id, user), user));

  route('PATCH', '/api/games/:id', ({ user, params, body }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user); requireLive(g);
    // Validate everything before touching the game so a bad field changes nothing.
    const next = {};
    if (body.name != null) next.name = normName(body.name).slice(0, 40) || g.name;
    if (body.location != null) next.location = normName(body.location).slice(0, 60);
    if (body.notes != null) next.notes = String(body.notes).slice(0, 300);
    if (body.date != null && /^\d{4}-\d{2}-\d{2}$/.test(body.date)) next.date = body.date;
    if (body.buyIns != null) next.buyIns = buyInList(body.buyIns);
    if (body.allowCustom != null) next.allowCustom = !!body.allowCustom;
    if (body.currency != null) next.currency = CURRENCIES.includes(body.currency) ? body.currency : fail(400, 'Pick a currency');
    if (body.chipValue != null) next.chipValue = money(body.chipValue, 'Chip value');
    Object.assign(g, next);
    log(g, user, `${user.name} updated the table settings`);
    return gameView(g, user);
  });

  route('DELETE', '/api/games/:id', ({ user, params }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user);
    delete db.games[g.id];
    return { ok: true };
  });

  route('GET', '/api/invite/:code', ({ params }) => {
    const g = Object.values(db.games).find((x) => x.code === String(params.code).toUpperCase());
    if (!g) fail(404, 'This invite link is not valid');
    return {
      id: g.id, name: g.name, date: g.date, location: g.location, status: g.status, currency: g.currency,
      chipValue: g.chipValue, buyIns: g.buyIns, host: nameOf(g.adminId), players: g.players.map((p) => nameOf(p.userId)),
    };
  });

  route('POST', '/api/invite/:code/join', ({ user, params }) => {
    const g = Object.values(db.games).find((x) => x.code === String(params.code).toUpperCase());
    if (!g) fail(404, 'This invite link is not valid');
    if (!g.players.some((p) => p.userId === user.id)) {
      requireLive(g);
      g.players.push({ userId: user.id, joinedAt: now() });
      log(g, user, `${user.name} joined the table`);
    }
    return { id: g.id };
  });

  route('POST', '/api/games/:id/invite/reset', ({ user, params }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user);
    g.code = inviteCode();
    log(g, user, `${user.name} made a new invite link (the old one stopped working)`);
    return gameView(g, user);
  });

  route('POST', '/api/games/:id/entries', ({ user, params, body }) => {
    const g = getGame(params.id, user);
    requireLive(g);
    const admin = isAdmin(g, user);
    const target = body.userId && body.userId !== user.id ? body.userId : user.id;
    if (target !== user.id && !admin) fail(403, 'You can only add entries for yourself');
    if (!g.players.some((p) => p.userId === target)) fail(400, 'That player is not at this table');
    const amount = money(body.amount);
    if (!admin && !g.allowCustom && !g.buyIns.includes(amount)) fail(400, 'Pick one of the entry options');
    // The host's own entries, and entries the host adds for others, need no approval.
    const status = admin ? 'approved' : 'pending';
    const entry = { id: id(), userId: target, amount, status, requestedBy: user.id, createdAt: now(), decidedAt: admin ? now() : null };
    g.entries.push(entry);
    log(g, user, admin
      ? `${user.name} added ${fmt(g, amount)} for ${nameOf(target)}`
      : `${user.name} asked to buy in for ${fmt(g, amount)}`);
    return gameView(g, user);
  });

  function findEntry(g, entryId) {
    const e = g.entries.find((x) => x.id === entryId);
    if (!e) fail(404, 'Entry not found');
    return e;
  }

  route('POST', '/api/games/:id/entries/:eid/approve', ({ user, params }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user); requireLive(g);
    const e = findEntry(g, params.eid);
    if (e.status !== 'approved') {
      e.status = 'approved'; e.decidedAt = now();
      log(g, user, `${user.name} approved ${fmt(g, e.amount)} for ${nameOf(e.userId)}`);
    }
    return gameView(g, user);
  });

  route('POST', '/api/games/:id/entries/approve-all', ({ user, params }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user); requireLive(g);
    const pending = g.entries.filter((e) => e.status === 'pending');
    for (const e of pending) { e.status = 'approved'; e.decidedAt = now(); }
    if (pending.length) log(g, user, `${user.name} approved ${pending.length} entries`);
    return gameView(g, user);
  });

  route('POST', '/api/games/:id/entries/:eid/reject', ({ user, params }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user); requireLive(g);
    const e = findEntry(g, params.eid);
    if (e.status !== 'pending') fail(409, 'Only pending entries can be rejected');
    g.entries = g.entries.filter((x) => x !== e);
    log(g, user, `${user.name} declined ${fmt(g, e.amount)} for ${nameOf(e.userId)}`);
    return gameView(g, user);
  });

  route('PATCH', '/api/games/:id/entries/:eid', ({ user, params, body }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user); requireLive(g);
    const e = findEntry(g, params.eid);
    const before = e.amount;
    e.amount = money(body.amount);
    log(g, user, `${user.name} changed ${nameOf(e.userId)}'s entry from ${fmt(g, before)} to ${fmt(g, e.amount)}`);
    return gameView(g, user);
  });

  route('DELETE', '/api/games/:id/entries/:eid', ({ user, params }) => {
    const g = getGame(params.id, user);
    requireLive(g);
    const e = findEntry(g, params.eid);
    // Players may withdraw their own request while it is still waiting; everything else is the host's call.
    const ownPending = e.userId === user.id && e.status === 'pending';
    if (!isAdmin(g, user) && !ownPending) fail(403, 'Only the host can delete entries');
    g.entries = g.entries.filter((x) => x !== e);
    log(g, user, ownPending && !isAdmin(g, user)
      ? `${user.name} withdrew a ${fmt(g, e.amount)} request`
      : `${user.name} deleted ${nameOf(e.userId)}'s ${fmt(g, e.amount)} entry`);
    return gameView(g, user);
  });

  route('PUT', '/api/games/:id/cashouts/:uid', ({ user, params, body }) => {
    const g = getGame(params.id, user);
    requireLive(g);
    if (params.uid !== user.id && !isAdmin(g, user)) fail(403, 'Only the host can set other players\' chips');
    if (!g.players.some((p) => p.userId === params.uid)) fail(400, 'That player is not at this table');
    if (body.chips === null || body.chips === '') {
      delete g.cashouts[params.uid];
      log(g, user, `${user.name} cleared ${nameOf(params.uid)}'s final chips`);
    } else {
      const chips = chipCount(body.chips);
      g.cashouts[params.uid] = { chips, setBy: user.id, at: now() };
      log(g, user, `${user.name} set ${nameOf(params.uid)}'s final chips to ${chips}`);
    }
    return gameView(g, user);
  });

  route('DELETE', '/api/games/:id/players/:uid', ({ user, params }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user); requireLive(g);
    if (params.uid === g.adminId) fail(400, 'Hand over hosting before leaving the table');
    g.players = g.players.filter((p) => p.userId !== params.uid);
    g.entries = g.entries.filter((e) => e.userId !== params.uid);
    delete g.cashouts[params.uid];
    log(g, user, `${user.name} removed ${nameOf(params.uid)} from the table`);
    return gameView(g, user);
  });

  route('POST', '/api/games/:id/host', ({ user, params, body }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user);
    if (!g.players.some((p) => p.userId === body.userId)) fail(400, 'That player is not at this table');
    g.adminId = body.userId;
    log(g, user, `${user.name} handed hosting to ${nameOf(body.userId)}`);
    return gameView(g, user);
  });

  route('POST', '/api/games/:id/end', ({ user, params, body }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user); requireLive(g);
    endGame(g, !!body.force);
    log(g, user, `${user.name} ended the night`);
    return gameView(g, user);
  });

  route('POST', '/api/games/:id/reopen', ({ user, params }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user);
    if (g.status === 'live') return gameView(g, user);
    g.status = 'live'; g.endedAt = null; g.settlements = [];
    log(g, user, `${user.name} reopened the table`);
    return gameView(g, user);
  });

  route('POST', '/api/games/:id/settlements/:idx', ({ user, params, body }) => {
    const g = getGame(params.id, user);
    const t = (g.settlements || [])[Number(params.idx)];
    if (!t) fail(404, 'Payment not found');
    if (![t.from, t.to, g.adminId].includes(user.id)) fail(403, 'Only the two players or the host can mark this');
    t.paid = !!body.paid;
    log(g, user, `${user.name} marked ${nameOf(t.from)} → ${nameOf(t.to)} ${fmt(g, t.amount)} as ${t.paid ? 'paid' : 'not paid'}`);
    return gameView(g, user);
  });

  route('GET', '/api/stats', ({ user }) => {
    const games = Object.values(db.games);
    const players = [...coPlayerIds(user)].map((uid) => {
      const s = statsFor(uid, games);
      const byCurrency = {};
      for (const [cur, v] of Object.entries(s.byCurrency)) {
        const { results, curve, ...rest } = v;
        byCurrency[cur] = rest;
      }
      return { user: publicUser(db.users[uid]), byCurrency, badges: badges(s.primary && s.byCurrency[s.primary]) };
    }).filter((p) => p.user);
    const currencies = [...new Set(players.flatMap((p) => Object.keys(p.byCurrency)))];
    return { players, currencies };
  });

  route('GET', '/api/players/:uid', ({ user, params }) => {
    if (!coPlayerIds(user).has(params.uid)) fail(404, 'Player not found');
    const target = db.users[params.uid];
    if (!target) fail(404, 'Player not found');
    const s = statsFor(target.id, Object.values(db.games));
    return { user: publicUser(target), stats: s, badges: badges(s.primary && s.byCurrency[s.primary]) };
  });

  // ---- http plumbing ------------------------------------------------------
  const OPEN = new Set(['POST /api/signup', 'POST /api/login']);
  const OPEN_RE = /^GET \/api\/invite\/[^/]+$/;

  function readBody(req) {
    return new Promise((resolve, reject) => {
      let size = 0; const chunks = [];
      req.on('data', (c) => { size += c.length; if (size > 64e3) { reject(new HttpError(413, 'Too large')); req.destroy(); } else chunks.push(c); });
      req.on('end', () => {
        if (!chunks.length) return resolve({});
        try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')) || {}); } catch { reject(new HttpError(400, 'Bad JSON')); }
      });
      req.on('error', reject);
    });
  }

  function send(res, status, obj) {
    res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify(obj));
  }

  function serveStatic(req, res, pathname) {
    const m = pathname.match(/^\/j\/([A-Za-z0-9]+)$/);
    if (m) { res.writeHead(302, { Location: `/#/join/${m[1].toUpperCase()}` }); return res.end(); }
    let rel = decodeURIComponent(pathname);
    if (rel === '/' || !path.extname(rel)) rel = '/index.html';
    const file = path.join(PUBLIC_DIR, path.normalize(rel));
    if (!file.startsWith(PUBLIC_DIR)) { res.writeHead(403); return res.end(); }
    fs.readFile(file, (err, buf) => {
      if (err) { res.writeHead(404); return res.end('Not found'); }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
      res.end(buf);
    });
  }

  async function handle(req, res) {
    const { pathname } = new URL(req.url, 'http://x');
    if (!pathname.startsWith('/api/')) return serveStatic(req, res, pathname);
    try {
      const r = routes.find((x) => x.method === req.method && x.re.test(pathname));
      if (!r) fail(404, 'Not found');
      const match = pathname.match(r.re);
      const params = {};
      r.keys.forEach((k, i) => { params[k] = decodeURIComponent(match[i + 1]); });
      const body = req.method === 'GET' ? {} : await readBody(req);
      const sig = `${req.method} ${pathname}`;
      const user = OPEN.has(sig) || OPEN_RE.test(sig) ? null : auth(req);
      const result = r.handler({ req, user, params, body });
      if (req.method !== 'GET') store.save();
      send(res, 200, result);
    } catch (err) {
      if (err instanceof HttpError) send(res, err.status, { error: err.message, ...(err.extra || {}) });
      else { console.error(err); send(res, 500, { error: 'Something went wrong' }); }
    }
  }

  return { handle };
}

module.exports = { createApi };
