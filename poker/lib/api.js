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
  if (!/^\d{4,6}$/.test(String(pin || ''))) fail(400, 'הקוד צריך להיות 4–6 ספרות');
}
function checkName(name) {
  const n = normName(name);
  if (n.length < 2 || n.length > 24) fail(400, 'השם צריך להיות באורך 2–24 תווים');
  return n;
}
function money(v, label = 'הסכום') {
  const n = Number(v);
  if (!Number.isFinite(n) || n <= 0 || n > 1e7) fail(400, `${label} חייב להיות מספר חיובי`);
  return round2(n);
}
function chipCount(v) {
  const n = Number(v);
  if (!Number.isFinite(n) || n < 0 || n > 1e8) fail(400, 'מספר הז׳יטונים חייב להיות 0 או יותר');
  return round2(n);
}
function buyInList(list) {
  if (!Array.isArray(list)) fail(400, 'חסרים סכומי כניסה');
  const clean = [...new Set(list.map((v) => money(v, 'סכום כניסה')))].sort((a, b) => a - b);
  if (!clean.length || clean.length > 8) fail(400, 'הוסיפו בין 1 ל־8 סכומי כניסה');
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
    if (!user) fail(401, 'צריך להתחבר');
    s.seenAt = now();
    return user;
  }

  function getGame(gameId, user) {
    const g = db.games[gameId];
    if (!g) fail(404, 'הערב לא נמצא');
    if (user && !g.players.some((p) => p.userId === user.id)) fail(403, 'אתם לא יושבים בשולחן הזה');
    return g;
  }
  const isAdmin = (g, user) => g.adminId === user.id;
  function requireAdmin(g, user) { if (!isAdmin(g, user)) fail(403, 'רק המארח של הערב יכול לעשות את זה'); }
  function requireLive(g) { if (g.status !== 'live') fail(409, 'הערב הזה נסגר. המארח יכול לפתוח אותו מחדש כדי לשנות.'); }
  function log(g, user, text) {
    g.log.unshift({ at: now(), by: user ? user.id : null, text });
    if (g.log.length > 300) g.log.length = 300;
    g.updatedAt = now();
  }
  const nameOf = (uid) => (db.users[uid] ? db.users[uid].name : 'מישהו');
  const SYMBOL = { ILS: '₪', USD: '$', EUR: '€', GBP: '£' };
  // Isolated left-to-right so amounts read correctly inside Hebrew sentences.
  const fmt = (g, n) => `\u2066${SYMBOL[g.currency] || ''}${round2(n)}\u2069`;

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
    if (t.pendingEntries) fail(409, 'קודם צריך לאשר או לדחות את הבקשות שמחכות');
    if (t.missingCashouts.length) {
      fail(409, `חסרה ספירת ז׳יטונים סופית של: ${t.missingCashouts.map(nameOf).join(', ')}`, { code: 'missing' });
    }
    if (!t.balanced && !force) {
      fail(409, `הז׳יטונים לא מסתדרים: היציאות ${t.difference > 0 ? 'גבוהות' : 'נמוכות'} מהקופה ב־${fmt(g, Math.abs(t.difference))}`, { code: 'unbalanced', difference: t.difference });
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
    if (userByName(name)) fail(409, 'השם הזה כבר תפוס. התחברו אליו, או הוסיפו אות משם המשפחה.');
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
    if (f && f.count >= 8) fail(429, 'יותר מדי ניסיונות עם קוד שגוי. נסו שוב בעוד כמה דקות.');
    const user = userByName(body.name);
    if (!user || hashPin(body.pin, user.salt) !== user.pinHash) {
      failures.set(key, { count: (f ? f.count : 0) + 1, first: f ? f.first : now() });
      fail(401, 'שם או קוד שגויים');
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
      if (other && other.id !== user.id) fail(409, 'השם הזה כבר תפוס');
    }
    if (body.pin != null) {
      checkPin(body.pin);
      if (hashPin(body.currentPin, user.salt) !== user.pinHash) fail(403, 'הקוד הנוכחי שגוי');
    }
    if (name) { user.name = name; user.key = nameKey(name); }
    if (body.pin != null) { user.salt = id(12); user.pinHash = hashPin(body.pin, user.salt); }
    if (body.color != null && COLORS.includes(body.color)) user.color = body.color;
    return { user: publicUser(user) };
  });

  route('POST', '/api/games', ({ user, body }) => {
    const currency = CURRENCIES.includes(body.currency) ? body.currency : fail(400, 'בחרו מטבע');
    const g = {
      id: id(), code: inviteCode(), adminId: user.id, status: 'live',
      name: normName(body.name).slice(0, 40) || `ערב פוקר ${today()}`,
      date: /^\d{4}-\d{2}-\d{2}$/.test(body.date || '') ? body.date : today(),
      location: normName(body.location).slice(0, 60),
      notes: String(body.notes || '').slice(0, 300),
      currency, chipValue: money(body.chipValue, 'שווי הז׳יטון'), buyIns: buyInList(body.buyIns),
      allowCustom: !!body.allowCustom,
      players: [{ userId: user.id, joinedAt: now() }],
      entries: [], cashouts: {}, settlements: [], log: [],
      createdAt: now(), updatedAt: now(), endedAt: null,
    };
    db.games[g.id] = g;
    log(g, user, `${user.name} · פתיחת השולחן`);
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
    if (body.currency != null) next.currency = CURRENCIES.includes(body.currency) ? body.currency : fail(400, 'בחרו מטבע');
    if (body.chipValue != null) next.chipValue = money(body.chipValue, 'שווי הז׳יטון');
    Object.assign(g, next);
    log(g, user, `${user.name} · עדכון הגדרות השולחן`);
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
    if (!g) fail(404, 'קישור ההזמנה לא תקף');
    return {
      id: g.id, name: g.name, date: g.date, location: g.location, status: g.status, currency: g.currency,
      chipValue: g.chipValue, buyIns: g.buyIns, host: nameOf(g.adminId), players: g.players.map((p) => nameOf(p.userId)),
    };
  });

  route('POST', '/api/invite/:code/join', ({ user, params }) => {
    const g = Object.values(db.games).find((x) => x.code === String(params.code).toUpperCase());
    if (!g) fail(404, 'קישור ההזמנה לא תקף');
    if (!g.players.some((p) => p.userId === user.id)) {
      requireLive(g);
      g.players.push({ userId: user.id, joinedAt: now() });
      log(g, user, `${user.name} · הצטרפות לשולחן`);
    }
    return { id: g.id };
  });

  route('POST', '/api/games/:id/invite/reset', ({ user, params }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user);
    g.code = inviteCode();
    log(g, user, `${user.name} · קישור הזמנה חדש (הישן הפסיק לעבוד)`);
    return gameView(g, user);
  });

  route('POST', '/api/games/:id/entries', ({ user, params, body }) => {
    const g = getGame(params.id, user);
    requireLive(g);
    const admin = isAdmin(g, user);
    const target = body.userId && body.userId !== user.id ? body.userId : user.id;
    if (target !== user.id && !admin) fail(403, 'אפשר להוסיף כניסות רק לעצמכם');
    if (!g.players.some((p) => p.userId === target)) fail(400, 'השחקן הזה לא יושב בשולחן');
    const amount = money(body.amount);
    if (!admin && !g.allowCustom && !g.buyIns.includes(amount)) fail(400, 'בחרו אחד מסכומי הכניסה');
    // The host's own entries, and entries the host adds for others, need no approval.
    const status = admin ? 'approved' : 'pending';
    const entry = { id: id(), userId: target, amount, status, requestedBy: user.id, createdAt: now(), decidedAt: admin ? now() : null };
    g.entries.push(entry);
    log(g, user, admin
      ? `${user.name} · הוספת ${fmt(g, amount)} ל${nameOf(target)}`
      : `${user.name} · בקשת כניסה ב־${fmt(g, amount)}`);
    return gameView(g, user);
  });

  function findEntry(g, entryId) {
    const e = g.entries.find((x) => x.id === entryId);
    if (!e) fail(404, 'הכניסה לא נמצאה');
    return e;
  }

  route('POST', '/api/games/:id/entries/:eid/approve', ({ user, params }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user); requireLive(g);
    const e = findEntry(g, params.eid);
    if (e.status !== 'approved') {
      e.status = 'approved'; e.decidedAt = now();
      log(g, user, `${user.name} · אישור ${fmt(g, e.amount)} ל${nameOf(e.userId)}`);
    }
    return gameView(g, user);
  });

  route('POST', '/api/games/:id/entries/approve-all', ({ user, params }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user); requireLive(g);
    const pending = g.entries.filter((e) => e.status === 'pending');
    for (const e of pending) { e.status = 'approved'; e.decidedAt = now(); }
    if (pending.length) log(g, user, `${user.name} · אישור ${pending.length} כניסות`);
    return gameView(g, user);
  });

  route('POST', '/api/games/:id/entries/:eid/reject', ({ user, params }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user); requireLive(g);
    const e = findEntry(g, params.eid);
    if (e.status !== 'pending') fail(409, 'אפשר לדחות רק בקשות שמחכות');
    g.entries = g.entries.filter((x) => x !== e);
    log(g, user, `${user.name} · דחיית ${fmt(g, e.amount)} של ${nameOf(e.userId)}`);
    return gameView(g, user);
  });

  route('PATCH', '/api/games/:id/entries/:eid', ({ user, params, body }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user); requireLive(g);
    const e = findEntry(g, params.eid);
    const before = e.amount;
    e.amount = money(body.amount);
    log(g, user, `${user.name} · שינוי כניסה של ${nameOf(e.userId)} מ־${fmt(g, before)} ל־${fmt(g, e.amount)}`);
    return gameView(g, user);
  });

  route('DELETE', '/api/games/:id/entries/:eid', ({ user, params }) => {
    const g = getGame(params.id, user);
    requireLive(g);
    const e = findEntry(g, params.eid);
    // Players may withdraw their own request while it is still waiting; everything else is the host's call.
    const ownPending = e.userId === user.id && e.status === 'pending';
    if (!isAdmin(g, user) && !ownPending) fail(403, 'רק המארח יכול למחוק כניסות');
    g.entries = g.entries.filter((x) => x !== e);
    log(g, user, ownPending && !isAdmin(g, user)
      ? `${user.name} · ביטול בקשה של ${fmt(g, e.amount)}`
      : `${user.name} · מחיקת כניסה של ${fmt(g, e.amount)} של ${nameOf(e.userId)}`);
    return gameView(g, user);
  });

  route('PUT', '/api/games/:id/cashouts/:uid', ({ user, params, body }) => {
    const g = getGame(params.id, user);
    requireLive(g);
    if (params.uid !== user.id && !isAdmin(g, user)) fail(403, 'רק המארח יכול לעדכן ז׳יטונים של שחקנים אחרים');
    if (!g.players.some((p) => p.userId === params.uid)) fail(400, 'השחקן הזה לא יושב בשולחן');
    if (body.chips === null || body.chips === '') {
      delete g.cashouts[params.uid];
      log(g, user, `${user.name} · ניקוי הספירה הסופית של ${nameOf(params.uid)}`);
    } else {
      const chips = chipCount(body.chips);
      g.cashouts[params.uid] = { chips, setBy: user.id, at: now() };
      log(g, user, `${user.name} · ספירה סופית של ${nameOf(params.uid)}: ${chips} ז׳יטונים`);
    }
    return gameView(g, user);
  });

  route('DELETE', '/api/games/:id/players/:uid', ({ user, params }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user); requireLive(g);
    if (params.uid === g.adminId) fail(400, 'קודם העבירו את האירוח למישהו אחר');
    g.players = g.players.filter((p) => p.userId !== params.uid);
    g.entries = g.entries.filter((e) => e.userId !== params.uid);
    delete g.cashouts[params.uid];
    log(g, user, `${user.name} · הוצאת ${nameOf(params.uid)} מהשולחן`);
    return gameView(g, user);
  });

  route('POST', '/api/games/:id/host', ({ user, params, body }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user);
    if (!g.players.some((p) => p.userId === body.userId)) fail(400, 'השחקן הזה לא יושב בשולחן');
    g.adminId = body.userId;
    log(g, user, `${user.name} · העברת האירוח ל${nameOf(body.userId)}`);
    return gameView(g, user);
  });

  route('POST', '/api/games/:id/end', ({ user, params, body }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user); requireLive(g);
    endGame(g, !!body.force);
    log(g, user, `${user.name} · סגירת הערב`);
    return gameView(g, user);
  });

  route('POST', '/api/games/:id/reopen', ({ user, params }) => {
    const g = getGame(params.id, user);
    requireAdmin(g, user);
    if (g.status === 'live') return gameView(g, user);
    g.status = 'live'; g.endedAt = null; g.settlements = [];
    log(g, user, `${user.name} · פתיחת השולחן מחדש`);
    return gameView(g, user);
  });

  route('POST', '/api/games/:id/settlements/:idx', ({ user, params, body }) => {
    const g = getGame(params.id, user);
    const t = (g.settlements || [])[Number(params.idx)];
    if (!t) fail(404, 'התשלום לא נמצא');
    if (![t.from, t.to, g.adminId].includes(user.id)) fail(403, 'רק שני השחקנים או המארח יכולים לסמן את זה');
    t.paid = !!body.paid;
    log(g, user, `${user.name} · ${nameOf(t.from)} ← ${nameOf(t.to)} ${fmt(g, t.amount)}: ${t.paid ? 'שולם' : 'לא שולם'}`);
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
    if (!coPlayerIds(user).has(params.uid)) fail(404, 'השחקן לא נמצא');
    const target = db.users[params.uid];
    if (!target) fail(404, 'השחקן לא נמצא');
    const s = statsFor(target.id, Object.values(db.games));
    return { user: publicUser(target), stats: s, badges: badges(s.primary && s.byCurrency[s.primary]) };
  });

  // ---- http plumbing ------------------------------------------------------
  const OPEN = new Set(['POST /api/signup', 'POST /api/login']);
  const OPEN_RE = /^GET \/api\/invite\/[^/]+$/;

  function readBody(req) {
    return new Promise((resolve, reject) => {
      let size = 0; const chunks = [];
      req.on('data', (c) => { size += c.length; if (size > 64e3) { reject(new HttpError(413, 'הבקשה גדולה מדי')); req.destroy(); } else chunks.push(c); });
      req.on('end', () => {
        if (!chunks.length) return resolve({});
        try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')) || {}); } catch { reject(new HttpError(400, 'בקשה לא תקינה')); }
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
      if (err) { res.writeHead(404); return res.end('לא נמצא'); }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
      res.end(buf);
    });
  }

  // Runs one API call. Kept free of HTTP so the browser demo can call it directly.
  function dispatch(method, pathname, headers, body) {
    try {
      const r = routes.find((x) => x.method === method && x.re.test(pathname));
      if (!r) fail(404, 'לא נמצא');
      const match = pathname.match(r.re);
      const params = {};
      r.keys.forEach((k, i) => { params[k] = decodeURIComponent(match[i + 1]); });
      const req = { headers };
      const sig = `${method} ${pathname}`;
      const user = OPEN.has(sig) || OPEN_RE.test(sig) ? null : auth(req);
      const result = r.handler({ req, user, params, body: body || {} });
      if (method !== 'GET') store.save();
      return { status: 200, body: result };
    } catch (err) {
      if (err instanceof HttpError) return { status: err.status, body: { error: err.message, ...(err.extra || {}) } };
      console.error(err);
      return { status: 500, body: { error: 'משהו השתבש' } };
    }
  }

  async function handle(req, res) {
    const { pathname } = new URL(req.url, 'http://x');
    if (!pathname.startsWith('/api/')) return serveStatic(req, res, pathname);
    let body = {};
    if (req.method !== 'GET') {
      try { body = await readBody(req); } catch (err) { return send(res, err.status || 400, { error: err.message }); }
    }
    const out = dispatch(req.method, pathname, req.headers, body);
    send(res, out.status, out.body);
  }

  return { handle, dispatch };
}

module.exports = { createApi };
